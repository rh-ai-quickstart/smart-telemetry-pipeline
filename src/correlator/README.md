# Correlator

Consumes OpenTelemetry logs and traces from Kafka topics (`otlp_logs`, `otlp_spans`), correlates them by traceId in Infinispan, and detects errors. When cached events expire (after a configurable TTL), the traceId is forwarded to a JMS queue for analysis by the analyzer.

## Running Locally

```bash
camel run *.camel.yaml *.xsl *.json --dev --prop=application-dev.properties
```

## Exporting

```bash
camel export --runtime=quarkus --directory=./quarkus *.camel.yaml *.xsl *.json
```
