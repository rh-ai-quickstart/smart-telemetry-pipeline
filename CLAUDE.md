# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Smart Telemetry Pipeline is an intelligent observability system that detects microservice errors in distributed applications, correlates OpenTelemetry logs and traces, and uses GenAI (LLM) to provide SREs with actionable remediation steps. It is built entirely with **Apache Camel JBang** (YAML DSL routes, no compiled Java). Target deployment is the **Red Hat Developer Sandbox** (OpenShift).

## Architecture

The system consists of three Camel applications that communicate via **ActiveMQ Artemis (JMS)** queues:

**Correlator** (`src/correlator/`) — Consumes OpenTelemetry logs and traces from **Kafka** topics (`otlp_logs`, `otlp_spans`), transforms them via XSLT data mappers (Kaoto-generated), and stores correlated events in **Infinispan** cache keyed by traceId. ERROR-severity events are placed in a TTL-based `events-to-process` cache; on expiration, the traceId is sent to the analyzer via JMS. Also handles per-trace custom prompt storage in Infinispan's `ai-messages` cache.

**Analyzer** (`src/analyzer/`) — Receives traceIds from JMS, retrieves correlated events from Infinispan, sends them with a configurable prompt/system-prompt to an **OpenAI-compatible LLM** for root cause analysis, and publishes the result back to JMS. Supports both automatic (cache-expiry triggered) and interactive (user-triggered) analysis modes. Exposes a status API on port 8089.

**UI Console** (`src/ui-console/`) — REST API + static HTML frontend on port 8080. Serves analysis results stored as files, proxies Prometheus metrics from all three services, exposes Infinispan cache stats and Artemis queue stats. Handles interactive analysis requests by forwarding to the analyzer via JMS.

### Data Flow

```
OTel Collector → Kafka → Correlator → Infinispan (events cache)
                                    ↓ (on TTL expiry or user trigger)
                              JMS (error-logs queue)
                                    ↓
                              Analyzer → LLM API
                                    ↓
                              JMS (analysis-result queue)
                                    ↓
                              UI Console → file storage → REST API
```

### Infrastructure Dependencies

- **Kafka** — receives OTLP telemetry from OTel Collector (topics: `otlp_logs`, `otlp_spans`)
- **Infinispan** — caches: `events` (correlated telemetry), `events-to-process` (TTL-triggered error processing), `ai-messages` (LLM prompts)
- **ActiveMQ Artemis** — JMS queues: `error-logs`, `error-logs-interactive`, `analysis-result`, `ai-prompts`, `ai-prompts-read`
- **OpenTelemetry Collector** — receives OTLP and exports to Kafka
- **OpenAI-compatible LLM** — for root cause analysis (configured via `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_MODEL` env vars)

## Running Locally

Run each Camel application (requires [Camel JBang CLI](https://camel.apache.org/manual/camel-jbang.html)):
```bash
# Correlator (Prometheus metrics on :9090)
camel run src/correlator/*.camel.yaml src/correlator/*.xsl src/correlator/*.json --dev --prop=src/correlator/application-dev.properties

# Analyzer (REST on :8089, Prometheus on :9091) — needs OPENAI_* env vars
camel run src/analyzer/*.camel.yaml --dev --prop=src/analyzer/application-dev.properties

# UI Console (REST on :8080, Prometheus on :9082)
camel run src/ui-console/*.camel.yaml src/ui-console/index.html --dev --prop=src/ui-console/application-dev.properties
```

## Deploying to OpenShift (Developer Sandbox)

Automated install and cleanup scripts:
```bash
./create.sh   # deploys infrastructure, configures OpenAI credentials, builds and deploys apps
./delete.sh   # removes everything
```

Manual steps are documented in `README.md`. The build pipeline uses Tekton to first build the `camel-launcher` image internally (downloading the JAR from Maven Central via `mvn dependency:copy`), then run `camel export --runtime=quarkus`, compile with Maven, and push container images via Buildah to the OpenShift internal registry. The camel-launcher version is configurable via the `camel-launcher-version` pipeline parameter (default: `4.20.0`).

### Log Generator (test data)

```bash
./log-generator/run.sh      # builds and deploys the log generator (simulates orders with 30% failure rate)
./log-generator/delete.sh   # removes log generator resources
```

The log generator uses the OTel Java agent to export logs and traces to the OTel Collector. Its Tekton pipeline is self-contained (all source files are embedded inline, no git clone required).

## Repository Structure

- `src/` — Camel JBang application source (YAML routes, properties, schemas, XSL mappers)
- `chart/` — Helm chart for OpenShift deployment (templates, values, per-component properties)
- `deploy/pipeline/`, `deploy/tasks/` — Tekton pipeline and tasks for OpenShift CI/CD
- `deploy/pipelinerun/` — Example PipelineRun manifests
- `deploy/resources/` — OpenShift resource manifests (Kafka, Infinispan, Artemis, OTel Collector, secrets, ConfigMaps)
- `log-generator/` — Simulated order-processing app for generating test telemetry (Tekton pipeline, run/delete scripts)
- `create.sh` / `delete.sh` — Automated install/cleanup scripts for Developer Sandbox

## Key Conventions

- Routes are defined in Camel YAML DSL (`*.camel.yaml`); the visual editor Kaoto can open these files.
- Data mapping between OTel JSON schemas and correlated schemas uses XSLT generated by Kaoto DataMapper (`kaoto-datamapper-*.xsl`).
- Configuration is split: `application-dev.properties` for local, `application-prod-quarkus.properties` (in `chart/properties/`) for OpenShift.
- Metrics are exposed via Micrometer/Prometheus on dedicated management ports per service.
- The `events-to-process` Infinispan cache uses TTL-based expiration as a deliberate delay mechanism — it waits for all related spans/logs to arrive before triggering analysis.
- On Developer Sandbox, OpenShift AI shared models (Granite) require a ServiceAccount token as the API key and a service CA truststore for TLS — the Helm chart handles this via an init container when `serviceCa.enabled=true`.
