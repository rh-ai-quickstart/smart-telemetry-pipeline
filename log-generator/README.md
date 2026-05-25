# Log Generator

Builds and deploys a Camel application that simulates order processing with random failures (30% failure rate) to generate realistic telemetry data for testing the Smart Telemetry Pipeline.

The image is built with the OpenTelemetry Java agent bundled in, so no external operator or `Instrumentation` CR is needed. Logs and traces are exported via OTLP to the OTel Collector, which forwards them to Kafka for the correlator to process.

## Setup

```bash
# Deploy the log generator
./log-generator/run.sh

# Remove the log generator
./log-generator/delete.sh
```

The scripts must be run from the repository root directory.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `namespace` | `slog-analyzer` | Target namespace for the image and deployment |
| `otel-collector-endpoint` | `http://camel-otel-collector-opentelemetry-collector.slog-analyzer.svc:4317` | OTLP collector endpoint |
| `camel-image` | `quay.io/mcarlett/camel-launcher:4.20.0` | Base image for the Camel JBang runtime |

The `run.sh` script automatically detects the current namespace and adjusts the OTel Collector endpoint accordingly.

## How It Works

The log generator runs two Camel routes:

- **order-processor** — Simulates order processing every 2 seconds. Each order goes through validation, and 30% of orders fail with one of three error types: database connection failure, payment gateway timeout, or authentication failure.
- **health-checker** — Emits a DEBUG-level health check log every 5 seconds.

The OpenTelemetry Java agent instruments the application, producing both logs and traces that flow through the pipeline:

```
Log Generator → OTel Collector → Kafka → Correlator → Infinispan → Analyzer → LLM
```
