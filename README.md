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

| Service | Port | Description |
|---|---|---|
| Prometheus | 9090 | Metrics collection & query engine |
| Grafana | 3000 | Dashboard & visualization |
| Node Exporter | 9100 | Host metrics (CPU, RAM, Disk, Network) |
| cAdvisor | 8080 | Container metrics |

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

SSH เข้า server ที่ต้องการ monitor แล้วรัน:

#### Option A: Docker (แนะนำ)

```bash
docker run -d \
  --name node-exporter \
  --restart unless-stopped \
  --net host \
  --pid host \
  -v /proc:/host/proc:ro \
  -v /sys:/host/sys:ro \
  -v /:/rootfs:ro \
  prom/node-exporter:latest \
  --path.procfs=/host/proc \
  --path.sysfs=/host/sys \
  --path.rootfs=/rootfs \
  --collector.filesystem.mount-points-exclude="^/(sys|proc|dev|host|etc)($$|/)"
```

#### Option B: Docker Compose

สร้างไฟล์ `docker-compose.yml` บน remote server:

```yaml
services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    network_mode: host
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - "--path.procfs=/host/proc"
      - "--path.sysfs=/host/sys"
      - "--path.rootfs=/rootfs"
      - "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"
```

```bash
docker compose up -d
```

#### Option C: Systemd (without Docker)

```bash
# Download
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar xvfz node_exporter-1.8.2.linux-amd64.tar.gz
sudo mv node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/

# Create systemd service
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

# Enable & start
sudo systemctl daemon-reload
sudo systemctl enable --now node-exporter
```

#### Verify installation

```bash
curl http://localhost:9100/metrics | head
```

### Step 2 - Open firewall (if needed)

```bash
# UFW
sudo ufw allow 9100/tcp

# firewalld
sudo firewall-cmd --permanent --add-port=9100/tcp
sudo firewall-cmd --reload

# iptables
sudo iptables -A INPUT -p tcp --dport 9100 -j ACCEPT
```

> **Security Tip:** จำกัด access เฉพาะ IP ของ Prometheus server
> ```bash
> sudo ufw allow from <PROMETHEUS_SERVER_IP> to any port 9100
> ```

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

| Dashboard | ID | Description |
|---|---|---|
| Node Exporter Full | `1860` | Host metrics ครบทุก metric |
| Docker Container | `893` | Container metrics จาก cAdvisor |
| Prometheus Stats | `2` | Prometheus self-monitoring |

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
