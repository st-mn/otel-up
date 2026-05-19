# otel-up

One-command OpenTelemetry + Grafana observability stack with automatic app instrumentation.

Spin up a full production-grade observability stack on any Ubuntu server in under 5 minutes — or deploy it to Kubernetes with the bundled Helm chart. Automatically instruments your Node.js, Python, Go, or Java app with no code changes required.

## What it deploys

| Service | Purpose | Port |
|---------|---------|------|
| OpenTelemetry Collector | Receives and routes telemetry | 4317 gRPC, 4318 HTTP |
| Prometheus | Metrics storage | 9090 |
| Loki | Log aggregation | 3100 |
| Tempo | Distributed tracing | 3200 |
| Grafana | Unified dashboards | 3000 |

All services are pre-wired together and provisioned automatically.

## Quick start (Ubuntu / Docker)

```bash
# Download scripts
curl -O https://raw.githubusercontent.com/st-mn/otel-up/main/otelsetup.sh
curl -O https://raw.githubusercontent.com/st-mn/otel-up/main/otelteardown.sh
chmod +x otelsetup.sh otelteardown.sh

# Deploy stack and instrument your app
bash otelsetup.sh /path/to/your/app

# Grafana URL is printed at the end
```

## Helm Chart (Kubernetes)

For Kubernetes deployments, the chart is published to GitHub Pages and can be installed directly:

```bash
helm repo add otel-up https://st-mn.github.io/otel-up
helm repo update
helm install otel-up otel-up/otel-up
```

To install in a dedicated namespace:

```bash
helm install otel-up otel-up/otel-up --namespace observability --create-namespace
```

Access Grafana:

```bash
kubectl port-forward svc/otel-up-grafana 3000:3000
# open http://localhost:3000  (admin / admin)
```

Send telemetry from in-cluster apps to:

```
otel-up-otelcollector.<namespace>.svc.cluster.local:4317   # OTLP gRPC
http://otel-up-otelcollector.<namespace>.svc.cluster.local:4318   # OTLP HTTP
```

### Key values.yaml options

| Key | Default | Description |
|-----|---------|-------------|
| `otelcollector.enabled` | `true` | Deploy the OTel Collector |
| `otelcollector.image.tag` | `latest` | Collector image tag |
| `otelcollector.resources` | see values | CPU/memory limits & requests |
| `otelcollector.config` | `""` | Raw collector config — overrides default pipeline |
| `prometheus.enabled` | `true` | Deploy Prometheus |
| `prometheus.persistence.enabled` | `false` | Use a PVC instead of emptyDir |
| `prometheus.persistence.size` | `10Gi` | PVC size |
| `prometheus.scrapeInterval` | `15s` | Global scrape interval |
| `loki.enabled` | `true` | Deploy Loki |
| `loki.persistence.enabled` | `false` | Use a PVC instead of emptyDir |
| `tempo.enabled` | `true` | Deploy Tempo |
| `tempo.persistence.enabled` | `false` | Use a PVC instead of emptyDir |
| `grafana.enabled` | `true` | Deploy Grafana |
| `grafana.adminUser` | `admin` | Grafana admin username |
| `grafana.adminPassword` | `admin` | Grafana admin password (change me) |
| `grafana.anonymousAccess.enabled` | `true` | Allow anonymous access |
| `grafana.persistence.enabled` | `false` | Use a PVC instead of emptyDir |
| `grafana.ingress.enabled` | `false` | Expose Grafana via Ingress |
| `grafana.ingress.hosts` | `grafana.local` | Ingress hosts |

To customize, pass `--set key=value` or use a values file:

```bash
helm install otel-up otel-up/otel-up -f my-values.yaml
```

> The shell scripts (`otelsetup.sh`, `otelteardown.sh`) are for bare Ubuntu servers using Docker Compose. The Helm chart in `charts/otel-up/` is the equivalent for Kubernetes.

## Auto-instrumentation (shell-script flow)

The setup script detects your app type and installs the OTel SDK automatically:

| Detected by | Language | What gets installed |
|-------------|----------|---------------------|
| package.json | Node.js | @opentelemetry/sdk-node + auto-instrumentation |
| requirements.txt | Python | opentelemetry-distro + bootstrap |
| go.mod | Go | OTel SDK via go get |
| pom.xml / build.gradle | Java | Java agent JAR |

A `.env.otel` file is written to your app directory. Source it before starting your app.

## Tear down

```bash
bash otelteardown.sh
```

Removes all Docker containers, volumes, and config. App SDK packages and instrumentation code are NOT touched.

For the Helm chart:

```bash
helm uninstall otel-up
```

## Requirements

**Shell-script flow:**
- Ubuntu 20.04 or any Docker-capable Linux
- 4GB RAM recommended
- Ports 3000, 3100, 3200, 4317, 4318, 9090 available

**Helm chart:**
- Kubernetes 1.20+
- Helm 3.x

## Files

| File / Directory | Description |
|------|-------------|
| `otelsetup.sh` | Full stack setup + app auto-instrumentation (Docker Compose) |
| `otelteardown.sh` | Infrastructure teardown, instrumentation preserved |
| `charts/otel-up/` | Helm chart for Kubernetes deployment |

## Architecture

```
Your App
   |
   +--> OTel Collector (4317/4318)
              +--> Prometheus --> Grafana (metrics)
              +--> Loki       --> Grafana (logs)
              +--> Tempo      --> Grafana (traces)
```
