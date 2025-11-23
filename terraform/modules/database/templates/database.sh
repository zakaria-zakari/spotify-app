#!/bin/bash
set -euxo pipefail

devicename="/dev/xvdf"
mountpoint="/var/lib/pgsql"

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib lvm2 amazon-cloudwatch-agent xfsprogs rsync
dnf -y update
dnf install -y postgresql-server postgresql-contrib lvm2 amazon-cloudwatch-agent xfsprogs rsync
PG_CONF_DIR="/etc/postgresql/$${PG_VERSION}/main"
PG_VERSION=$(psql -V | awk '{print $3}' | cut -d. -f1)
PG_DATA_DIR="/var/lib/pgsql/data"
PG_DATA_DIR="/var/lib/postgresql/$${PG_VERSION}/main"

if [ ! -e "$devicename" ]; then
  devicename="/dev/nvme1n1"
fi

if ! blkid "$devicename" >/dev/null 2>&1; then
  mkfs.xfs "$devicename"
fi

mkdir -p "$mountpoint"
if ! mountpoint -q "$mountpoint"; then
  mount "$devicename" "$mountpoint"
fi

if ! grep -q "$mountpoint" /etc/fstab; then
  uuid=$(blkid -s UUID -o value "$devicename")
  echo "UUID=$uuid $mountpoint xfs defaults,nofail 0 2" >>/etc/fstab
fi

chown -R postgres:postgres "$mountpoint"
chmod 700 "$mountpoint"
# Stop service if running
systemctl stop postgresql || true

# Initialize database if missing
if [ ! -f "$PG_DATA_DIR/PG_VERSION" ]; then
  postgresql-setup --initdb
fi

systemctl start postgresql
systemctl start postgresql

sudo -u postgres psql <<SQL
DO
$$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${db_username}') THEN
      CREATE ROLE ${db_username} LOGIN PASSWORD '${db_password}';
   END IF;
END
$$;

CREATE DATABASE playlistparser OWNER ${db_username};
GRANT ALL PRIVILEGES ON DATABASE playlistparser TO ${db_username};
SQL
cat <<CONF >$${PG_DATA_DIR}/pg_hba.conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
host    playlistparser  ${db_username}  10.0.0.0/8              md5
CONF
CONF
if ! grep -q "^listen_addresses" "$${PG_DATA_DIR}/postgresql.conf"; then
  echo "listen_addresses = '*'" >>"$${PG_DATA_DIR}/postgresql.conf"
fi

# Enable basic logging to file so CloudWatch can collect
if ! grep -q "^logging_collector" "$${PG_DATA_DIR}/postgresql.conf"; then
  echo "logging_collector = on" >>"$${PG_DATA_DIR}/postgresql.conf"
  echo "log_directory = 'log'" >>"$${PG_DATA_DIR}/postgresql.conf"
  echo "log_filename = 'postgresql.log'" >>"$${PG_DATA_DIR}/postgresql.conf"
fi

systemctl restart postgresql
  echo "listen_addresses = '*'" >>"$${PG_CONF_DIR}/postgresql.conf"
fi

systemctl restart postgresql

cat <<CWAGENT >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "logs": {
            "file_path": "/var/lib/pgsql/data/log/postgresql.log",
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/postgresql/postgresql-$${PG_VERSION}-main.log",
            "log_group_name": "${environment}-playlistparser-database",
            "log_stream_name": "postgres"
          }
        ]
      }
    }
systemctl enable amazon-cloudwatch-agent || true
systemctl restart amazon-cloudwatch-agent || true
CWAGENT

systemctl enable amazon-cloudwatch-agent
pg_isready -h localhost -p 5432

cat <<'HEALTH' >/usr/local/bin/db-healthz.sh
#!/bin/bash
pg_isready -h localhost -p 5432
HEALTH
chmod +x /usr/local/bin/db-healthz.sh
