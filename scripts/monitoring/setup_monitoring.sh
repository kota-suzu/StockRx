#!/bin/bash

# ================================================================================
# StockRx Monitoring & Alerting Setup Script
# Comprehensive monitoring solution with Prometheus, Grafana, and AlertManager
# ================================================================================

set -euo pipefail

# Configuration
MONITORING_DIR="/app/monitoring"
PROMETHEUS_VERSION="v2.45.0"
GRAFANA_VERSION="10.0.0"
ALERTMANAGER_VERSION="v0.25.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create monitoring directory structure
setup_directories() {
    log_info "Setting up monitoring directories..."
    
    mkdir -p "$MONITORING_DIR"/{prometheus,grafana,alertmanager,configs,dashboards,rules}
    mkdir -p "$MONITORING_DIR"/data/{prometheus,grafana,alertmanager}
    
    log_success "Monitoring directories created"
}

# Generate Prometheus configuration
create_prometheus_config() {
    log_info "Creating Prometheus configuration..."
    
    cat > "$MONITORING_DIR/configs/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "/etc/prometheus/rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  # StockRx Application Metrics
  - job_name: 'stockrx-app'
    static_configs:
      - targets: ['web:3000']
    metrics_path: '/metrics'
    scrape_interval: 10s
    scrape_timeout: 5s

  # System Metrics (Node Exporter)
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  # Database Metrics (MySQL Exporter)
  - job_name: 'mysql-exporter'
    static_configs:
      - targets: ['mysql-exporter:9104']

  # Redis Metrics
  - job_name: 'redis-exporter'
    static_configs:
      - targets: ['redis-exporter:9121']

  # Docker Metrics
  - job_name: 'docker'
    static_configs:
      - targets: ['docker-exporter:9323']

  # Prometheus Self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF

    log_success "Prometheus configuration created"
}

# Generate alert rules
create_alert_rules() {
    log_info "Creating alert rules..."
    
    cat > "$MONITORING_DIR/rules/stockrx_alerts.yml" << 'EOF'
groups:
  - name: stockrx.rules
    rules:
      # Application Health Alerts
      - alert: StockRxDown
        expr: up{job="stockrx-app"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "StockRx application is down"
          description: "StockRx application has been down for more than 1 minute"

      - alert: HighResponseTime
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High response time detected"
          description: "95th percentile response time is {{ $value }}s"

      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value | humanizePercentage }}"

      # Database Alerts
      - alert: DatabaseDown
        expr: up{job="mysql-exporter"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "MySQL database is down"
          description: "MySQL database has been unreachable for more than 1 minute"

      - alert: HighDatabaseConnections
        expr: mysql_global_status_threads_connected / mysql_global_variables_max_connections > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High database connection usage"
          description: "Database connection usage is {{ $value | humanizePercentage }}"

      - alert: SlowQueries
        expr: rate(mysql_global_status_slow_queries[5m]) > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High number of slow queries"
          description: "{{ $value }} slow queries per second"

      # System Resource Alerts
      - alert: HighCPUUsage
        expr: (100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage"
          description: "CPU usage is {{ $value }}%"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage"
          description: "Memory usage is {{ $value }}%"

      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 15
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Low disk space"
          description: "Disk space is {{ $value }}% full"

      # Redis Alerts
      - alert: RedisDown
        expr: up{job="redis-exporter"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Redis is down"
          description: "Redis has been unreachable for more than 1 minute"

      - alert: HighRedisMemoryUsage
        expr: redis_memory_used_bytes / redis_memory_max_bytes > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High Redis memory usage"
          description: "Redis memory usage is {{ $value | humanizePercentage }}"
EOF

    log_success "Alert rules created"
}

# Generate AlertManager configuration
create_alertmanager_config() {
    log_info "Creating AlertManager configuration..."
    
    cat > "$MONITORING_DIR/configs/alertmanager.yml" << 'EOF'
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alerts@stockrx.example.com'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'
  routes:
    - match:
        severity: critical
      receiver: 'critical-alerts'
    - match:
        severity: warning
      receiver: 'warning-alerts'

receivers:
  - name: 'web.hook'
    webhook_configs:
      - url: 'http://localhost:5001/'

  - name: 'critical-alerts'
    slack_configs:
      - api_url: '${SLACK_WEBHOOK_URL}'
        channel: '#alerts-critical'
        title: '🚨 Critical Alert: {{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
        send_resolved: true
    email_configs:
      - to: 'devops@stockrx.example.com'
        subject: '🚨 StockRx Critical Alert'
        body: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

  - name: 'warning-alerts'
    slack_configs:
      - api_url: '${SLACK_WEBHOOK_URL}'
        channel: '#alerts-warning'
        title: '⚠️ Warning: {{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
        send_resolved: true

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
EOF

    log_success "AlertManager configuration created"
}

# Generate Grafana dashboards
create_grafana_dashboards() {
    log_info "Creating Grafana dashboards..."
    
    # StockRx Application Dashboard
    cat > "$MONITORING_DIR/dashboards/stockrx_dashboard.json" << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "StockRx Application Metrics",
    "tags": ["stockrx"],
    "style": "dark",
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Request Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])",
            "legendFormat": "Requests/sec"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "reqps"
          }
        },
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 0,
          "y": 0
        }
      },
      {
        "id": 2,
        "title": "Response Time",
        "type": "timeseries",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))",
            "legendFormat": "95th percentile"
          },
          {
            "expr": "histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))",
            "legendFormat": "50th percentile"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "s"
          }
        },
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 12,
          "y": 0
        }
      },
      {
        "id": 3,
        "title": "Error Rate",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(http_requests_total{status=~\"5..\"}[5m]) / rate(http_requests_total[5m])",
            "legendFormat": "Error Rate"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percentunit"
          }
        },
        "gridPos": {
          "h": 8,
          "w": 24,
          "x": 0,
          "y": 8
        }
      }
    ],
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "refresh": "30s"
  }
}
EOF

    log_success "Grafana dashboards created"
}

# Generate docker-compose for monitoring stack
create_monitoring_compose() {
    log_info "Creating monitoring docker-compose configuration..."
    
    cat > "$MONITORING_DIR/docker-compose.monitoring.yml" << 'EOF'
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:v2.45.0
    container_name: stockrx-prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./configs/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./rules:/etc/prometheus/rules
      - ./data/prometheus:/prometheus
    networks:
      - monitoring

  alertmanager:
    image: prom/alertmanager:v0.25.0
    container_name: stockrx-alertmanager
    restart: unless-stopped
    ports:
      - "9093:9093"
    volumes:
      - ./configs/alertmanager.yml:/etc/alertmanager/config.yml
      - ./data/alertmanager:/alertmanager
    command:
      - '--config.file=/etc/alertmanager/config.yml'
      - '--storage.path=/alertmanager'
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:10.0.0
    container_name: stockrx-grafana
    restart: unless-stopped
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-admin}
    volumes:
      - ./data/grafana:/var/lib/grafana
      - ./dashboards:/etc/grafana/provisioning/dashboards
    networks:
      - monitoring

  node-exporter:
    image: prom/node-exporter:latest
    container_name: stockrx-node-exporter
    restart: unless-stopped
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - monitoring

  mysql-exporter:
    image: prom/mysqld-exporter:latest
    container_name: stockrx-mysql-exporter
    restart: unless-stopped
    ports:
      - "9104:9104"
    environment:
      - DATA_SOURCE_NAME=${DB_USER:-root}:${DB_PASSWORD:-password}@(mysql:3306)/
    networks:
      - monitoring

  redis-exporter:
    image: oliver006/redis_exporter:latest
    container_name: stockrx-redis-exporter
    restart: unless-stopped
    ports:
      - "9121:9121"
    environment:
      - REDIS_ADDR=redis://redis:6379
    networks:
      - monitoring

networks:
  monitoring:
    driver: bridge

volumes:
  prometheus_data:
  grafana_data:
  alertmanager_data:
EOF

    log_success "Monitoring docker-compose configuration created"
}

# Generate monitoring startup script
create_startup_script() {
    log_info "Creating monitoring startup script..."
    
    cat > "$MONITORING_DIR/start_monitoring.sh" << 'EOF'
#!/bin/bash

set -euo pipefail

MONITORING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting StockRx monitoring stack..."

# Set proper permissions
chmod -R 755 "$MONITORING_DIR/data"

# Start monitoring services
cd "$MONITORING_DIR"
docker-compose -f docker-compose.monitoring.yml up -d

echo "Monitoring services started!"
echo ""
echo "Access URLs:"
echo "  - Prometheus: http://localhost:9090"
echo "  - Grafana: http://localhost:3001 (admin/admin)"
echo "  - AlertManager: http://localhost:9093"
echo ""
echo "Wait a few minutes for metrics to be collected before viewing dashboards."
EOF

    chmod +x "$MONITORING_DIR/start_monitoring.sh"
    
    log_success "Monitoring startup script created"
}

# Generate health check script
create_health_check_script() {
    log_info "Creating comprehensive health check script..."
    
    cat > "$MONITORING_DIR/health_check.sh" << 'EOF'
#!/bin/bash

# ================================================================================
# StockRx Comprehensive Health Check Script
# ================================================================================

set -euo pipefail

# Configuration
ENDPOINTS=(
    "http://localhost:3000/health:StockRx Application"
    "http://localhost:9090/-/healthy:Prometheus"
    "http://localhost:3001/api/health:Grafana"
    "http://localhost:9093/-/healthy:AlertManager"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_endpoint() {
    local url="$1"
    local name="$2"
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s "$url" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ $name${NC} - Healthy"
            return 0
        fi
        ((attempt++))
        sleep 1
    done
    
    echo -e "${RED}❌ $name${NC} - Unhealthy (URL: $url)"
    return 1
}

main() {
    echo "🏥 StockRx System Health Check"
    echo "=================================="
    
    local overall_health=0
    
    for endpoint in "${ENDPOINTS[@]}"; do
        IFS=':' read -r url name <<< "$endpoint"
        if ! check_endpoint "$url" "$name"; then
            overall_health=1
        fi
    done
    
    echo ""
    if [ $overall_health -eq 0 ]; then
        echo -e "${GREEN}🎉 All systems healthy!${NC}"
    else
        echo -e "${RED}⚠️  Some systems are unhealthy${NC}"
    fi
    
    return $overall_health
}

main "$@"
EOF

    chmod +x "$MONITORING_DIR/health_check.sh"
    
    log_success "Health check script created"
}

# Main setup function
main() {
    log_info "Setting up StockRx monitoring and alerting..."
    
    setup_directories
    create_prometheus_config
    create_alert_rules
    create_alertmanager_config
    create_grafana_dashboards
    create_monitoring_compose
    create_startup_script
    create_health_check_script
    
    log_success "Monitoring setup completed!"
    log_info ""
    log_info "Next steps:"
    log_info "1. Configure environment variables (SLACK_WEBHOOK_URL, GRAFANA_PASSWORD)"
    log_info "2. Run: cd $MONITORING_DIR && ./start_monitoring.sh"
    log_info "3. Import Grafana dashboards from the dashboards/ directory"
    log_info "4. Configure alert notification channels"
    log_info ""
    log_info "Documentation:"
    log_info "- Prometheus: http://localhost:9090"
    log_info "- Grafana: http://localhost:3001"
    log_info "- AlertManager: http://localhost:9093"
}

main "$@"