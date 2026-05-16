# otel-up

One-command OpenTelemetry + Grafana observability stack with automatic app instrumentation.

Spin up a full production-grade observability stack on any Ubuntu server in under 5 minutes. Automatically instruments your Node.js, Python, Go, or Java app with no code changes required.

## What it deploys

| Service | Purpose | Port |
|---------|---------|------|
| OpenTelemetry Collector | Receives and routes telemetry | 4317 gRPC, 4318 HTTP |
| Prometheus | Metrics storage | 9090 |
| Loki | Log aggregation | 3100 |
| Tempo | Distributed tracing | 3200 |
| Grafana | Unified dashboards | 3000 |

All services are pre-wired together and provisioned automatically.

## Quick start

    # Download scripts
        curl -O https://raw.githubusercontent.com/st-mn/otel-up/main/otel-setup.sh
            curl -O https://raw.githubusercontent.com/st-mn/otel-up/main/otel-teardown.sh
                chmod +x otel-setup.sh otel-teardown.sh

                    # Deploy stack and instrument your app
                        bash otel-setup.sh /path/to/your/app

                            # Grafana URL is printed at the end

                            ## Auto-instrumentation

                            The setup script detects your app type and installs the OTel SDK automatically:

                            | Detected by | Language | What gets installed |
                            |-------------|----------|---------------------|
                            | package.json | Node.js | @opentelemetry/sdk-node + auto-instrumentation |
                            | requirements.txt | Python | opentelemetry-distro + bootstrap |
                            | go.mod | Go | OTel SDK via go get |
                            | pom.xml / build.gradle | Java | Java agent JAR |

                            A .env.otel file is written to your app directory. Source it before starting your app.

                            ## Tear down

                                bash otel-teardown.sh

                                Removes all Docker containers, volumes, and config. App SDK packages and instrumentation code are NOT touched.

                                ## Requirements

                                - Ubuntu 20.04 or any Docker-capable Linux
                                - 4GB RAM recommended
                                - Ports 3000, 3100, 3200, 4317, 4318, 9090 available

                                ## Files

                                | File | Description |
                                |------|-------------|
                                | otel-setup.sh | Full stack setup + app auto-instrumentation |
                                | otel-teardown.sh | Infrastructure teardown, instrumentation preserved |

                                ## Architecture

                                    Your App
                                          |
                                                +--> OTel Collector (4317/4318)
                                                             +--> Prometheus --> Grafana (metrics)
                                                                          +--> Loki       --> Grafana (logs)
                                                                                       +--> Tempo      --> Grafana (traces)
                                                                                       
