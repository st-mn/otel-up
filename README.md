# otel-up

Automated Observability Provisioning - One-command OpenTelemetry + Grafana observability stack with automatic app instrumentation.

Spin up a full production-grade observability stack on any Ubuntu server in under 5 minutes w/ Docker — or deploy it to Kubernetes with the bundled Helm chart. Automatically instruments your Node.js, Python, Go, or Java app.

## What it deploys

| Service | Purpose | Port |
|---------|---------|------|
| OpenTelemetry Collector | Receives and routes telemetry | 4317 gRPC, 4318 HTTP |
| Prometheus | Metrics storage | 9090 |
| Loki | Log aggregation | 3100 |
| Tempo | Distributed tracing | 3200 |
| Grafana | Unified dashboards | 3000 |

All services are pre-wired together and provisioned automatically.

## Option 1 - Singleton Spin Up: Usage with Ubuntu / Docker

```bash
# Download scripts
curl -O https://raw.githubusercontent.com/st-mn/otel-up/main/otelsetup.sh
curl -O https://raw.githubusercontent.com/st-mn/otel-up/main/otelteardown.sh
chmod +x otelsetup.sh otelteardown.sh

# Deploy stack and instrument your app
bash otelsetup.sh /path/to/your/app

# Grafana URL is printed at the end
```

## Option 2 - Distributed Spin Up: Usage with Helm Chart / Kubernetes

For Kubernetes deployments, install the chart from this repository clone directly:

```bash
helm install otel-up ./charts/otel-up
```

To install in a dedicated namespace:

```bash
helm install otel-up ./charts/otel-up --namespace observability --create-namespace
```

Access Grafana:

```bash
kubectl port-forward svc/otel-up-grafana 3000:3000
# open http://localhost:3000 (admin / admin)
```

Send telemetry from in-cluster apps to:

```
otel-up-otelcollector.<namespace>.svc.cluster.local:4317 # OTLP gRPC
http://otel-up-otelcollector.<namespace>.svc.cluster.local:4318 # OTLP HTTP
```

### Key values.yaml options

| Key | Default | Description |
|-----|---------|-------------|
| `otelcollector.enabled` | `true` | Deploy the OTel Collector |
| `otelcollector.image.tag` | `0.111.0` | Collector image tag |
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
helm install otel-up ./charts/otel-up -f my-values.yaml
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

## GPU Monitoring (NVIDIA)

Enable full GPU observability — GPU Operator, DCGM Exporter, Prometheus scraping, Grafana dashboard, and alerting rules — in one command:

```sh
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install otel-up otel-up/otel-up \
  --set gpu-operator.enabled=true \
  --set gpuMetrics.enabled=true \
  --set gpuDashboard.enabled=true \
  --set gpuAlerts.enabled=true \
  --namespace observability \
  --create-namespace
```

This deploys:

| Component | What it does |
|-----------|-------------|
| **NVIDIA GPU Operator** | Installs drivers, container toolkit, device plugin, and DCGM Exporter on every GPU node automatically |
| **DCGM Exporter** | Exposes GPU metrics at `:9400/metrics`, scraped by Prometheus every 15s |
| **Prometheus** | Stores GPU metrics time-series |
| **Grafana** | Pre-loaded GPU dashboard (utilization, memory, power, temperature, tensor core, NVLink) |
| **Alert rules** | GPU utilization > 95%, memory > 90%, XID errors (driver crash), thermal throttling |

### Key GPU metrics collected

| Metric | Description |
|--------|-------------|
| `DCGM_FI_DEV_GPU_UTIL` | GPU compute utilization (%) |
| `DCGM_FI_DEV_FB_USED` | Framebuffer memory used (MiB) |
| `DCGM_FI_DEV_FB_FREE` | Framebuffer memory free (MiB) |
| `DCGM_FI_DEV_POWER_USAGE` | Power draw (W) |
| `DCGM_FI_DEV_SM_CLOCK` | Streaming multiprocessor clock (MHz) |
| `DCGM_FI_DEV_MEMORY_CLOCK` | Memory clock (MHz) |
| `DCGM_FI_DEV_GPU_TEMP` | GPU temperature (°C) |
| `DCGM_FI_DEV_THERMAL_VIOLATION_COUNT` | Thermal throttling events |
| `DCGM_FI_DEV_XID_ERRORS` | GPU driver/hardware errors (critical) |
| `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE` | Tensor core utilization (ratio) |
| `DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL` | NVLink bandwidth (MB/s) |
| `DCGM_FI_PROF_DRAM_ACTIVE` | DRAM active ratio |

### Requirements for GPU monitoring
- Kubernetes nodes with NVIDIA GPUs (A100, H100, or any NVIDIA data-centre GPU)
- Ubuntu 20.04 or 22.04 on GPU nodes (required by GPU Operator driver installer)
- GPU Operator installs drivers automatically if not present

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
     +--> Loki --> Grafana (logs)
     +--> Tempo --> Grafana (traces)
```
