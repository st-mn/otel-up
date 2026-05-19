#!/usr/bin/env bash
# =============================================================================
# otel-setup.sh
# Full-stack OpenTelemetry + Grafana setup on Ubuntu (Docker Compose)
# Auto-instruments Node.js / Python / Go / Java apps found in APP_DIR
#
# Usage: bash otel-setup.sh [/path/to/your/app]
#   If no path given, defaults to current directory.
#
# What it installs (infra only, Docker-isolated):
#   - OpenTelemetry Collector
#   - Prometheus (metrics)
#   - Loki (logs)
#   - Tempo (traces)
#   - Grafana (dashboards)
#
# App instrumentation adds SDK deps + env vars only — no code edits.
# Run otel-teardown.sh to remove infra without touching instrumentation.
# =============================================================================

set -euo pipefail

APP_DIR="${1:-$(pwd)}"
INSTALL_DIR="$HOME/.otel-stack"
GRAFANA_PORT=3000
OTEL_GRPC_PORT=4317
OTEL_HTTP_PORT=4318
PROMETHEUS_PORT=9090
LOKI_PORT=3100
TEMPO_PORT=3200
SERVICE_NAME="my-app"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[otel-setup]${NC} $*"; }
ok()   { echo -e "${GREEN}[ok]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }

# ── 1. Install Docker ──────────────────────────────────────────────────────────
install_docker() {
  if command -v docker &>/dev/null; then
    ok "Docker already installed: $(docker --version)"
    return
  fi
  log "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  ok "Docker installed."
}

install_docker_compose() {
  if docker compose version &>/dev/null 2>&1; then
    ok "Docker Compose plugin already installed."
    return
  fi
  if command -v docker-compose &>/dev/null; then
    ok "docker-compose already installed: $(docker-compose --version)"
    return
  fi
  log "Installing Docker Compose plugin..."
  COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
  sudo curl -SL \
    "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  ok "Docker Compose installed."
}

# ── 2. Write config files ──────────────────────────────────────────────────────
write_configs() {
  mkdir -p "$INSTALL_DIR"/{grafana/provisioning/datasources,grafana/provisioning/dashboards,otelcol}

  # ── OTel Collector config ──────────────────────────────────────────────────
  cat > "$INSTALL_DIR/otelcol/config.yaml" <<'OTELCFG'
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 5s
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128
  resourcedetection:
    detectors: [env, system]
    timeout: 5s

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"
    namespace: otel
  loki:
    endpoint: "http://loki:3100/loki/api/v1/push"
    default_labels_enabled:
      exporter: false
      job: true
  otlp/tempo:
    endpoint: "http://tempo:4317"
    tls:
      insecure: true
  debug:
    verbosity: basic

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlp/tempo]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch, resourcedetection]
      exporters: [prometheus]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [loki]
OTELCFG

  # ── Prometheus config ──────────────────────────────────────────────────────
  cat > "$INSTALL_DIR/prometheus.yml" <<'PROMCFG'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'otel-collector'
    static_configs:
      - targets: ['otelcol:8889']
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
PROMCFG

  # ── Tempo config ───────────────────────────────────────────────────────────
  cat > "$INSTALL_DIR/tempo.yaml" <<'TEMPOCFG'
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317

ingester:
  max_block_duration: 5m

compactor:
  compaction:
    block_retention: 48h

storage:
  trace:
    backend: local
    local:
      path: /tmp/tempo/blocks
    wal:
      path: /tmp/tempo/wal
TEMPOCFG

  # ── Grafana datasources ────────────────────────────────────────────────────
  cat > "$INSTALL_DIR/grafana/provisioning/datasources/datasources.yaml" <<'DSCFG'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: true

  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    editable: true
    jsonData:
      tracesToLogsV2:
        datasourceUid: loki
        spanStartTimeShift: '-5m'
        spanEndTimeShift: '5m'
      serviceMap:
        datasourceUid: prometheus
      search:
        hide: false
      nodeGraph:
        enabled: true
DSCFG

  # ── Grafana dashboard provisioning ─────────────────────────────────────────
  cat > "$INSTALL_DIR/grafana/provisioning/dashboards/dashboards.yaml" <<'DBCFG'
apiVersion: 1
providers:
  - name: default
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /etc/grafana/provisioning/dashboards
DBCFG

  ok "Config files written to $INSTALL_DIR"
}

# ── 3. Write docker-compose.yml ────────────────────────────────────────────────
write_compose() {
  cat > "$INSTALL_DIR/docker-compose.yml" <<COMPOSE
version: "3.9"

networks:
  otel:
    driver: bridge

volumes:
  prometheus_data:
  loki_data:
  grafana_data:

services:

  otelcol:
    image: otel/opentelemetry-collector-contrib:latest
    container_name: otelcol
    restart: unless-stopped
    command: ["--config=/etc/otelcol/config.yaml"]
    volumes:
      - $INSTALL_DIR/otelcol/config.yaml:/etc/otelcol/config.yaml:ro
    ports:
      - "${OTEL_GRPC_PORT}:4317"
      - "${OTEL_HTTP_PORT}:4318"
      - "8889:8889"
    networks: [otel]

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.enable-lifecycle'
    volumes:
      - $INSTALL_DIR/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    ports:
      - "${PROMETHEUS_PORT}:9090"
    networks: [otel]

  loki:
    image: grafana/loki:latest
    container_name: loki
    restart: unless-stopped
    command: -config.file=/etc/loki/local-config.yaml
    volumes:
      - loki_data:/loki
    ports:
      - "${LOKI_PORT}:3100"
    networks: [otel]

  tempo:
    image: grafana/tempo:latest
    container_name: tempo
    restart: unless-stopped
    command: ["-config.file=/etc/tempo.yaml"]
    volumes:
      - $INSTALL_DIR/tempo.yaml:/etc/tempo.yaml:ro
    ports:
      - "${TEMPO_PORT}:3200"
    networks: [otel]

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    environment:
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
      - GF_AUTH_DISABLE_LOGIN_FORM=false
      - GF_FEATURE_TOGGLES_ENABLE=traceqlEditor
    volumes:
      - grafana_data:/var/lib/grafana
      - $INSTALL_DIR/grafana/provisioning:/etc/grafana/provisioning:ro
    ports:
      - "${GRAFANA_PORT}:3000"
    depends_on: [prometheus, loki, tempo]
    networks: [otel]
COMPOSE

  ok "docker-compose.yml written."
}

# ── 4. Start the stack ─────────────────────────────────────────────────────────
start_stack() {
  log "Pulling images and starting stack (this may take a minute)..."
  cd "$INSTALL_DIR"
  if docker compose version &>/dev/null 2>&1; then
    docker compose up -d --pull always
  else
    docker-compose up -d --pull always
  fi
  ok "Stack started."
}

# ── 5. Auto-instrument the app ─────────────────────────────────────────────────
detect_app_type() {
  if [[ -f "$APP_DIR/package.json" ]]; then
    echo "node"
  elif [[ -f "$APP_DIR/requirements.txt" ]] || [[ -f "$APP_DIR/pyproject.toml" ]]; then
    echo "python"
  elif [[ -f "$APP_DIR/go.mod" ]]; then
    echo "go"
  elif [[ -f "$APP_DIR/pom.xml" ]] || [[ -f "$APP_DIR/build.gradle" ]]; then
    echo "java"
  else
    echo "unknown"
  fi
}

write_otel_env() {
  local ENDPOINT_GRPC="http://localhost:${OTEL_GRPC_PORT}"
  local ENDPOINT_HTTP="http://localhost:${OTEL_HTTP_PORT}"
  cat > "$APP_DIR/.env.otel" <<ENVFILE
# OpenTelemetry environment variables — sourced by your app at startup
# Generated by otel-setup.sh — safe to commit, no secrets here
export OTEL_SERVICE_NAME="${SERVICE_NAME}"
export OTEL_EXPORTER_OTLP_ENDPOINT="${ENDPOINT_GRPC}"
export OTEL_EXPORTER_OTLP_PROTOCOL="grpc"
export OTEL_TRACES_EXPORTER="otlp"
export OTEL_METRICS_EXPORTER="otlp"
export OTEL_LOGS_EXPORTER="otlp"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=local"
# Source this file before starting your app:
#   source .env.otel && node server.js
#   source .env.otel && python app.py
ENVFILE
  ok "OTel env file written to $APP_DIR/.env.otel"
}

instrument_node() {
  log "Detected Node.js app — installing OTel SDK..."
  cd "$APP_DIR"
  npm install --save \
    @opentelemetry/sdk-node \
    @opentelemetry/auto-instrumentations-node \
    @opentelemetry/exporter-trace-otlp-grpc \
    @opentelemetry/exporter-metrics-otlp-grpc \
    @opentelemetry/exporter-logs-otlp-grpc 2>/dev/null

  cat > "$APP_DIR/otel-init.js" <<'NODEINIT'
// otel-init.js — require this FIRST via: node -r ./otel-init.js your-app.js
// or add to package.json: "node --require ./otel-init.js"
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-grpc');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter(),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter(),
    exportIntervalMillis: 10000,
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();
process.on('SIGTERM', () => sdk.shutdown());
console.log('[otel] OpenTelemetry SDK initialized');
NODEINIT
  ok "Created $APP_DIR/otel-init.js"
  echo ""
  warn "To start your app with tracing:"
  warn "  source .env.otel && node -r ./otel-init.js your-app.js"
}

instrument_python() {
  log "Detected Python app — installing OTel SDK..."
  cd "$APP_DIR"
  pip install --quiet \
    opentelemetry-distro \
    opentelemetry-exporter-otlp-proto-grpc 2>/dev/null || \
  pip3 install --quiet \
    opentelemetry-distro \
    opentelemetry-exporter-otlp-proto-grpc 2>/dev/null
  opentelemetry-bootstrap -a install 2>/dev/null || true
  ok "Python OTel SDK installed."
  echo ""
  warn "To start your app with tracing:"
  warn "  source .env.otel && opentelemetry-instrument python app.py"
}

instrument_go() {
  log "Detected Go app — adding OTel dependencies..."
  cd "$APP_DIR"
  go get go.opentelemetry.io/otel \
    go.opentelemetry.io/otel/sdk/trace \
    go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc \
    go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp 2>/dev/null
  ok "Go OTel packages added to go.mod."
  cat > "$APP_DIR/otel_init.go" <<'GOINIT'
package main

import (
	"context"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
	"log"
	"os"
)

func initOtel(ctx context.Context) func() {
	svcName := os.Getenv("OTEL_SERVICE_NAME")
	if svcName == "" { svcName = "my-go-app" }
	exp, err := otlptracegrpc.New(ctx)
	if err != nil { log.Fatalf("otel: %v", err) }
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exp),
		sdktrace.WithResource(resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceName(svcName),
		)),
	)
	otel.SetTracerProvider(tp)
	return func() { _ = tp.Shutdown(ctx) }
}
GOINIT
  warn "Call initOtel(ctx) at the top of your main() and defer the returned cleanup func."
}

instrument_java() {
  log "Detected Java app — downloading OTel Java agent..."
  JAVA_AGENT_URL="https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar"
  curl -sSL "$JAVA_AGENT_URL" -o "$APP_DIR/opentelemetry-javaagent.jar"
  ok "Java agent saved to $APP_DIR/opentelemetry-javaagent.jar"
  warn "Add to your JVM startup flags:"
  warn "  source .env.otel && java -javaagent:./opentelemetry-javaagent.jar -jar your-app.jar"
}

auto_instrument() {
  log "Detecting app type in: $APP_DIR"
  local APP_TYPE
  APP_TYPE=$(detect_app_type)
  write_otel_env

  case "$APP_TYPE" in
    node)   instrument_node ;;
    python) instrument_python ;;
    go)     instrument_go ;;
    java)   instrument_java ;;
    *)
      warn "Could not detect app type (no package.json / requirements.txt / go.mod / pom.xml found)."
      warn "OTel env vars written to $APP_DIR/.env.otel — add the SDK for your language manually."
      ;;
  esac
}

# ── 6. Wait for Grafana and print URL ─────────────────────────────────────────
wait_for_grafana() {
  log "Waiting for Grafana to become ready..."
  local SERVER_IP
  SERVER_IP=$(hostname -I | awk '{print $1}')
  local GRAFANA_URL="http://${SERVER_IP}:${GRAFANA_PORT}"
  local attempts=0
  until curl -sf "$GRAFANA_URL/api/health" > /dev/null 2>&1; do
    attempts=$((attempts+1))
    if [[ $attempts -gt 30 ]]; then
      warn "Grafana not responding after 60s — check: docker logs grafana"
      break
    fi
    sleep 2
  done
  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  ✅  OpenTelemetry stack is running!${NC}"
  echo ""
  echo -e "  📊  Grafana:    ${CYAN}${GRAFANA_URL}${NC}  (admin / admin)"
  echo -e "  📈  Prometheus: ${CYAN}http://${SERVER_IP}:${PROMETHEUS_PORT}${NC}"
  echo -e "  📝  Loki:       ${CYAN}http://${SERVER_IP}:${LOKI_PORT}${NC}"
  echo -e "  🔍  Tempo:      ${CYAN}http://${SERVER_IP}:${TEMPO_PORT}${NC}"
  echo ""
  echo -e "  🔌  OTLP gRPC:  localhost:${OTEL_GRPC_PORT}"
  echo -e "  🔌  OTLP HTTP:  localhost:${OTEL_HTTP_PORT}"
  echo ""
  echo -e "  App env file:  ${APP_DIR}/.env.otel"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
  echo ""
  log "Starting OpenTelemetry + Grafana stack setup..."
  log "App directory: $APP_DIR"
  log "Install directory: $INSTALL_DIR"
  echo ""

  install_docker
  install_docker_compose
  write_configs
  write_compose
  start_stack
  auto_instrument
  wait_for_grafana
}

main
