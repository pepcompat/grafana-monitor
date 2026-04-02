<!-- @format -->

# Monitoring Stack

Grafana + Prometheus monitoring stack with Docker Compose

## Architecture

```
+-------------------+
|     Grafana       |  :3000  Dashboard & Visualization
+--------+----------+
         |
+--------v----------+
|    Prometheus      |  :9090  Metrics Storage & Query
+--------+----------+
         |
    +----+----+--------------------+
    |         |                    |
+---v---+ +---v--------+  +-------v--------+
| Node  | |  cAdvisor  |  | Remote Servers |
| Exp.  | |            |  | (Node Exporter)|
+-------+ +------------+  +----------------+
 :9100      :8080           :9100
```

| Service       | Port | Description                            |
| ------------- | ---- | -------------------------------------- |
| Prometheus    | 9090 | Metrics collection & query engine      |
| Grafana       | 3000 | Dashboard & visualization              |
| Node Exporter | 9100 | Host metrics (CPU, RAM, Disk, Network) |
| cAdvisor      | 8080 | Container metrics                      |

## Quick Start

### 1. Start monitoring stack

```bash
docker compose up -d
```

### 2. Access

- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090
- Prometheus Targets: http://localhost:9090/targets

### 3. Default credentials

Grafana login สามารถแก้ไขได้ที่ `.env`

```
Username: admin
Password: admin
```

## Monitor Remote Servers

### Step 1 - Install Node Exporter on remote server

SSH เข้า server ที่ต้องการ monitor แล้วรัน **install script** (แนะนำ):

```bash
curl -sfL https://raw.githubusercontent.com/pepcompat/grafana-monitor/refs/heads/main/scripts/install-node-exporter.sh | bash
```

หรือ copy script จาก `scripts/install-node-exporter.sh` ไปรันบน server โดยตรง:

```bash
scp scripts/install-node-exporter.sh user@<SERVER_IP>:/tmp/
ssh user@<SERVER_IP> "bash /tmp/install-node-exporter.sh"
```

Script จะติดตั้ง Node Exporter v1.10.2 พร้อม Basic Auth อัตโนมัติ

> **Credentials:** `prometheus` / `MonitorSecure2024!`

#### ติดตั้ง Manual (Systemd)

```bash
# Download
wget https://github.com/prometheus/node_exporter/releases/download/v1.10.2/node_exporter-1.10.2.linux-amd64.tar.gz
tar xvfz node_exporter-1.10.2.linux-amd64.tar.gz
sudo mv node_exporter-1.10.2.linux-amd64/node_exporter /usr/local/bin/

# Create Basic Auth config
sudo mkdir -p /etc/node-exporter
sudo tee /etc/node-exporter/web.yml > /dev/null <<'EOF'
basic_auth_users:
  prometheus: $2y$12$6W6SLbVVW/tQlss5EloNnuQPRCIvTiTBQ0gu170cf2W1KDBJYtX0O
EOF
sudo chmod 600 /etc/node-exporter/web.yml

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

# Enable & start
sudo systemctl daemon-reload
sudo systemctl enable --now node-exporter
```

#### Verify installation

```bash
# ใส่ credentials → ต้องได้ metrics
curl -u prometheus:MonitorSecure2024! http://localhost:9100/metrics | head

# ไม่ใส่ credentials → ต้องได้ 401 Unauthorized
curl -s -o /dev/null -w "%{http_code}" http://localhost:9100/metrics
```

### Step 2 - Open firewall (if needed)

```bash
# UFW
sudo ufw allow 9100/tcp

# firewalld
sudo firewall-cmd --permanent --add-port=9100/tcp
sudo firewall-cmd --reload
```

### Step 3 - Add target to Prometheus

แก้ไขไฟล์ `prometheus/prometheus.yml` เพิ่ม target:

```yaml
- job_name: "remote-servers"
  static_configs:
    - targets: ["192.168.1.10:9100"]
      labels:
        instance_name: "web-server-01"

    # เพิ่ม server ใหม่ตรงนี้
    - targets: ["<NEW_SERVER_IP>:9100"]
      labels:
        instance_name: "<SERVER_NAME>"
```

### Step 4 - Reload Prometheus

```bash
# Option A: API reload (ไม่ต้อง restart)
curl -X POST http://localhost:9090/-/reload

# Option B: Restart container
docker compose restart prometheus
```

### Step 5 - Verify

1. เปิด http://localhost:9090/targets
2. ตรวจสอบว่า target ใหม่ state เป็น **UP**

## Grafana Dashboards

Dashboard **Node Exporter Full** ถูก provision มาให้อัตโนมัติ

ใช้ dropdown **instance** ด้านบน dashboard เพื่อสลับดู server แต่ละตัว

### Import dashboard เพิ่มเติม

1. เปิด Grafana > **Dashboards** > **New** > **Import**
2. ใส่ Dashboard ID แล้วกด **Load**

| Dashboard          | ID     | Description                    |
| ------------------ | ------ | ------------------------------ |
| Node Exporter Full | `1860` | Host metrics ครบทุก metric     |
| Docker Container   | `893`  | Container metrics จาก cAdvisor |
| Prometheus Stats   | `2`    | Prometheus self-monitoring     |

## File Structure

```
monitor/
├── .env                                    # Grafana credentials
├── .gitignore
├── docker-compose.yml                      # Main stack
├── README.md
├── grafana/
│   ├── dashboards/
│   │   └── node-exporter-full.json         # Auto-provisioned dashboard
│   └── provisioning/
│       ├── dashboards/
│       │   └── dashboards.yml              # Dashboard provider config
│       └── datasources/
│           └── datasource.yml              # Prometheus datasource
└── prometheus/
    └── prometheus.yml                      # Scrape targets config
```

## Useful Commands

```bash
# Start
docker compose up -d

# Stop
docker compose down

# Stop & remove volumes (reset data)
docker compose down -v

# View logs
docker compose logs -f prometheus
docker compose logs -f grafana

# Reload Prometheus config (no restart)
curl -X POST http://localhost:9090/-/reload

# Check Prometheus config syntax
docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
```

```bash
wget https://github.com/prometheus/node_exporter/releases/download/v1.10.2/node_exporter-1.10.2.linux-amd64.tar.gz
tar xvfz node_exporter-1.10.2.linux-amd64.tar.gz
sudo mv node_exporter-1.10.2.linux-amd64/node_exporter /usr/local/bin/

sudo tee /etc/systemd/system/node-exporter.service > /dev/null <<'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node-exporter
```
