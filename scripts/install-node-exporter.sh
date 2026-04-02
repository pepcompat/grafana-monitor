#!/bin/bash
set -e

NODE_EXPORTER_VERSION="1.10.2"
AUTH_USER="prometheus"
# Password: MonitorSecure2024!
AUTH_HASH='$2y$12$6W6SLbVVW/tQlss5EloNnuQPRCIvTiTBQ0gu170cf2W1KDBJYtX0O'

echo "=== Installing Node Exporter v${NODE_EXPORTER_VERSION} with Basic Auth ==="

# Download & install
cd /tmp
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
sudo mv "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"*
echo "[OK] Binary installed"

# Create config directory & Basic Auth config
sudo mkdir -p /etc/node-exporter
sudo tee /etc/node-exporter/web.yml > /dev/null <<EOF
basic_auth_users:
  ${AUTH_USER}: ${AUTH_HASH}
EOF
sudo chmod 644 /etc/node-exporter/web.yml
echo "[OK] Basic Auth configured"

# Create systemd service
sudo tee /etc/systemd/system/node-exporter.service > /dev/null <<'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/node_exporter --web.config.file=/etc/node-exporter/web.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF
echo "[OK] Systemd service created"

# Stop existing service (if running)
if systemctl is-active --quiet node-exporter 2>/dev/null; then
    echo "[..] Stopping existing Node Exporter..."
    sudo systemctl stop node-exporter
fi

# Also remove old docker container (if exists)
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^node-exporter$'; then
    echo "[..] Removing old Docker container..."
    docker rm -f node-exporter 2>/dev/null || true
fi

# Enable & start
sudo systemctl daemon-reload
sudo systemctl enable --now node-exporter
echo "[OK] Node Exporter started"

# Verify
echo ""
echo "=== Verifying ==="
if curl -sf -u "${AUTH_USER}:MonitorSecure2024!" http://localhost:9100/metrics > /dev/null 2>&1; then
    echo "[OK] Basic Auth working - metrics accessible with credentials"
else
    echo "[WARN] Could not verify, check: sudo systemctl status node-exporter"
fi

if curl -sf http://localhost:9100/metrics > /dev/null 2>&1; then
    echo "[FAIL] Metrics accessible WITHOUT auth - something went wrong!"
else
    echo "[OK] Metrics blocked without credentials"
fi

echo ""
echo "=== Done! ==="
echo "Node Exporter: http://$(hostname -I | awk '{print $1}'):9100"
echo "Auth: ${AUTH_USER} / MonitorSecure2024!"
