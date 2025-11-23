#!/bin/bash
# Hardened user-data for playlistparser frontend
set -euo pipefail
LOG_FILE="/var/log/playlistparser-frontend-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "== [FRONTEND BOOT] Start $(date -u +'%Y-%m-%dT%H:%M:%SZ') =="

retry() {
  local attempts=$1; shift
  local delay=$1; shift
  local n=0
  until "$@"; do
    n=$((n+1))
    if [ $n -ge $attempts ]; then
      echo "Command failed after $attempts attempts: $*" >&2
      return 1
    fi
    echo "Retry $n/$attempts for: $*"; sleep $delay
  done
}

# Environment variables
cat <<'VAREOF' >/etc/profile.d/playlistparser-frontend.sh
%{ for key, value in environment_variables ~}
export ${key}="${value}"
%{ endfor ~}
VAREOF

source /etc/profile.d/playlistparser-frontend.sh

dnf -y update || true
retry 3 5 dnf install -y nginx git curl tar || true

if ! command -v node >/dev/null 2>&1; then
  echo "== Node not found; installing distribution nodejs =="
  retry 3 5 dnf install -y nodejs || {
    echo "Fallback: installing Node via tarball";
    curl -fsSL https://nodejs.org/dist/v20.11.1/node-v20.11.1-linux-x64.tar.xz -o /tmp/node.tar.xz || true
    tar -xf /tmp/node.tar.xz -C /usr/local --strip-components=1 || true
  }
fi
echo "Node version: $(node -v || echo missing)"

mkdir -p /opt/playlistparser
cd /opt/playlistparser

: "$${APP_SOURCE_URL:?APP_SOURCE_URL must be provided}"
SOURCE_DIR="/opt/playlistparser/source"
echo "== Fetching source repo =="
if [ ! -d "$SOURCE_DIR/.git" ]; then
  rm -rf "$SOURCE_DIR"
  retry 3 5 git clone "$APP_SOURCE_URL" "$SOURCE_DIR"
else
  cd "$SOURCE_DIR"
  git fetch --all --prune || true
  git reset --hard origin/HEAD || true
fi

cd "$SOURCE_DIR/frontend"
echo "== Installing dependencies =="
retry 3 5 npm install || { echo "npm install failed"; exit 1; }
echo "== Building frontend =="
npm run build || { echo "Build failed; deploying fallback index"; echo '<html><body><h1>Frontend build failed</h1></body></html>' > dist/index.html; }

rm -rf /var/www/html/*
cp -r dist/* /var/www/html/

cat <<'NGINX' >/etc/nginx/conf.d/playlistparser.conf
server {
  listen ${port};
  server_name _;

  root /var/www/html;
  index index.html;

  location / {
    try_files $uri $uri/ /index.html;
  }

  location = /healthz {
    access_log off;
    add_header Content-Type text/plain;
    return 200 'ok';
  }
}
NGINX
systemctl enable nginx
systemctl restart nginx || { echo "Nginx restart failed"; exit 1; }
echo "== Nginx started; probing health =="
curl -s -o /var/log/playlistparser-frontend-first-health.txt http://127.0.0.1:${port}/healthz || echo "frontend health probe failed" >> "$LOG_FILE"

%{ if enable_cloudwatch_agent }
dnf install -y amazon-cloudwatch-agent || true
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a stop || true
cat <<CWAGENT >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "${environment}-playlistparser-frontend",
            "log_stream_name": "nginx-access"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "${environment}-playlistparser-frontend",
            "log_stream_name": "nginx-error"
          }
        ]
      }
    }
  }
}
CWAGENT

systemctl enable amazon-cloudwatch-agent || true
systemctl restart amazon-cloudwatch-agent || true
echo "== CloudWatch agent restarted =="
%{ endif }
echo "== [FRONTEND BOOT] Complete $(date -u +'%Y-%m-%dT%H:%M:%SZ') =="
