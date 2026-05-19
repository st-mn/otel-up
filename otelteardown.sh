#!/usr/bin/env bash
# =============================================================================
# otel-teardown.sh
# Removes the OpenTelemetry + Grafana infrastructure stack completely.
#
# What it REMOVES:
#   - All Docker containers (otelcol, prometheus, loki, tempo, grafana)
#   - Docker volumes (prometheus_data, loki_data, grafana_data)
#   - Docker network (otel)
#   - Config files in ~/.otel-stack/
#
# What it KEEPS (untouched):
#   - Your app source code
#   - Installed OTel SDK packages (node_modules, pip packages, go.mod entries)
#   - otel-init.js / otel_init.go / opentelemetry-javaagent.jar
#   - .env.otel file in your app directory
#   - Any custom instrumentation you wrote
#
# Run: bash otel-teardown.sh
# =============================================================================

set -euo pipefail

INSTALL_DIR="$HOME/.otel-stack"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${CYAN}[otel-teardown]${NC} $*"; }
ok()   { echo -e "${GREEN}[ok]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }

confirm() {
  echo ""
  echo -e "${RED}⚠️  This will permanently delete all OTel infra (containers + volumes + configs).${NC}"
  echo -e "${YELLOW}    Your app instrumentation code and SDK packages will NOT be touched.${NC}"
  echo ""
  read -rp "    Type 'yes' to confirm teardown: " answer
  if [[ "$answer" != "yes" ]]; then
    echo "Aborted."
    exit 0
  fi
  echo ""
}

stop_containers() {
  if [[ ! -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    warn "No docker-compose.yml found at $INSTALL_DIR — skipping container teardown."
    return
  fi

  log "Stopping and removing containers..."
  cd "$INSTALL_DIR"
  if docker compose version &>/dev/null 2>&1; then
    docker compose down --volumes --remove-orphans 2>/dev/null || true
  elif command -v docker-compose &>/dev/null; then
    docker-compose down --volumes --remove-orphans 2>/dev/null || true
  else
    warn "Neither 'docker compose' nor 'docker-compose' found. Removing containers manually..."
    for name in otelcol prometheus loki tempo grafana; do
      docker rm -f "$name" 2>/dev/null && ok "Removed container: $name" || true
    done
    for vol in otel-stack_prometheus_data otel-stack_loki_data otel-stack_grafana_data; do
      docker volume rm "$vol" 2>/dev/null && ok "Removed volume: $vol" || true
    done
    docker network rm otel 2>/dev/null && ok "Removed network: otel" || true
  fi
  ok "Containers and volumes removed."
}

remove_configs() {
  if [[ -d "$INSTALL_DIR" ]]; then
    log "Removing config directory: $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
    ok "Config directory removed."
  else
    warn "$INSTALL_DIR not found — nothing to remove."
  fi
}

print_summary() {
  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  ✅  OTel infrastructure torn down successfully.${NC}"
  echo ""
  echo -e "  The following were ${RED}removed${NC}:"
  echo -e "    • Docker containers: otelcol, prometheus, loki, tempo, grafana"
  echo -e "    • Docker volumes:    prometheus_data, loki_data, grafana_data"
  echo -e "    • Config directory:  $INSTALL_DIR"
  echo ""
  echo -e "  The following were ${GREEN}kept${NC} (your instrumentation is safe):"
  echo -e "    • App source code & OTel SDK packages"
  echo -e "    • otel-init.js / otel_init.go / opentelemetry-javaagent.jar"
  echo -e "    • .env.otel in your app directory"
  echo ""
  echo -e "  To re-deploy the stack: ${CYAN}bash otel-setup.sh [/path/to/app]${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

main() {
  confirm
  stop_containers
  remove_configs
  print_summary
}

main
