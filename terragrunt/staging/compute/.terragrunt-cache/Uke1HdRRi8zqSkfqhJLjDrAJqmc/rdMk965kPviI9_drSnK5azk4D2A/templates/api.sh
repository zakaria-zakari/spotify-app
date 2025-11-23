#!/bin/bash
# Hardened user-data for playlistparser API
set -euo pipefail

LOG_FILE="/var/log/playlistparser-api-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "== [API BOOT] Start $(date -u +'%Y-%m-%dT%H:%M:%SZ') =="

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
cat <<'VAREOF' >/etc/profile.d/playlistparser-api.sh
%{ for key, value in environment_variables ~}
export ${key}="${value}"
%{ endfor ~}
VAREOF

source /etc/profile.d/playlistparser-api.sh

echo "== Installing base packages =="
dnf -y update || true
retry 3 5 dnf install -y git curl gcc-c++ make tar || true

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

cd "$SOURCE_DIR/api"

# Ensure API is mounted under base path if provided (e.g., /api) without requiring upstream code changes
if grep -q "app.register(authRoutes);" src/server.js; then
  sed -i 's|app.register(authRoutes);|app.register(authRoutes, { prefix: process.env.API_BASE_PATH || "" });|' src/server.js || true
fi
if grep -q "app.register(meRoutes);" src/server.js; then
  sed -i 's|app.register(meRoutes);|app.register(meRoutes, { prefix: process.env.API_BASE_PATH || "" });|' src/server.js || true
fi
if grep -q "app.register(playlistRoutes);" src/server.js; then
  sed -i 's|app.register(playlistRoutes);|app.register(playlistRoutes, { prefix: process.env.API_BASE_PATH || "" });|' src/server.js || true
fi
echo "== Installing dependencies =="
retry 3 5 npm install || { echo "npm install failed"; exit 1; }
echo "== Optional build step =="
npm run build || echo "Build step skipped/failed (non-fatal)"

cat <<'SERVICE' >/etc/systemd/system/playlistparser-api.service
[Unit]
Description=PXL Playlist Parser API
After=network.target

[Service]
EnvironmentFile=/etc/playlistparser-api.env
WorkingDirectory=/opt/playlistparser/source/api
ExecStart=/usr/bin/node server.js
Restart=on-failure
StandardOutput=append:/var/log/playlistparser-api.log
StandardError=append:/var/log/playlistparser-api.log

[Install]
WantedBy=multi-user.target
SERVICE

cat <<'ENVFILE' >/etc/playlistparser-api.env
PORT=${port}
%{ for key, value in environment_variables ~}
${key}="${value}"
%{ endfor ~}
ENVFILE

echo "== Registering systemd service =="
systemctl daemon-reload
systemctl enable playlistparser-api.service
systemctl restart playlistparser-api.service || {
  echo "Service failed to start; checking log"; journalctl -u playlistparser-api.service --no-pager -n 50 || true; }

echo "== Initial health probe =="
sleep 4
curl -s -o /var/log/playlistparser-api-first-health.json "http://127.0.0.1:${port}/healthz" || echo "local health probe failed" >> "$LOG_FILE"

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
            "file_path": "/var/log/playlistparser-api.log",
            "log_group_name": "${environment}-playlistparser-api",
            "log_stream_name": "api"
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

echo "== [API BOOT] Complete $(date -u +'%Y-%m-%dT%H:%M:%SZ') =="
