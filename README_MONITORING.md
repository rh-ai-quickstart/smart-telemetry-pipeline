# Monitoring and Alerting

The Helm chart deploys **ServiceMonitors** and a **PrometheusRule** that integrate with the OpenShift user-workload monitoring stack. All three Camel applications expose Prometheus metrics on port 9876 at `/observe/metrics`, which are scraped automatically.

> **Prerequisite:** User-workload monitoring must be enabled on the cluster. On clusters with `cluster-admin` access, enable it by setting `enableUserWorkload: true` in the `cluster-monitoring-config` ConfigMap in the `openshift-monitoring` namespace ([documentation](https://docs.redhat.com/en/documentation/monitoring_stack_for_red_hat_openshift/latest/html/configuring_user_workload_monitoring/index)). On the Developer Sandbox, user-workload monitoring may not be available — in that case, use the built-in **Infrastructure** dashboard in the UI Console application, which polls the same Prometheus metrics directly from the services.

## Viewing metrics in the OpenShift console

When user-workload monitoring is enabled, navigate to **Observe > Metrics** in the Developer perspective, select your project, and enter any of the PromQL queries below.

### Error detection and analysis

| Query | Description |
|-------|-------------|
| `correlator_errors_detected_total` | Total number of errors detected by the correlator |
| `rate(correlator_errors_detected_total[5m])` | Error detection rate (errors per second) |
| `analyzer_analyses_completed_total` | Total number of LLM analyses completed |
| `rate(analyzer_analyses_completed_total[5m])` | Analysis completion rate |

### Telemetry ingestion

| Query | Description |
|-------|-------------|
| `correlator_events_stored_total` | Total events stored in Infinispan (by `type`: `log` or `trace`) |
| `rate(correlator_events_stored_total[5m])` | Ingestion rate by type |
| `correlator_events_expired_total` | Events expired from cache and sent for analysis |

### LLM performance

| Query | Description |
|-------|-------------|
| `rate(analyzer_llm_duration_seconds_sum[5m]) / rate(analyzer_llm_duration_seconds_count[5m])` | Average LLM response time |
| `analyzer_llm_duration_seconds_count` | Total number of LLM API calls |

### UI Console

| Query | Description |
|-------|-------------|
| `ui_results_stored_total` | Analysis results saved to file storage |
| `ui_interactive_triggered_total` | Interactive analyses triggered by users |

## Alerts

The Helm chart includes a `PrometheusRule` with two alerts, visible under **Observe > Alerting**:

**ErrorDetected** (severity: `warning`)

Fires whenever the correlator detects new ERROR-severity events from the monitored microservices. This means the log generator (or any instrumented application) has produced errors that the correlator picked up from the Kafka telemetry stream. The alert remains active as long as errors keep arriving.

- **Expression:** `increase(correlator_errors_detected_total[1m]) > 0`
- **Source metric:** `correlator_errors_detected_total` — a counter incremented each time the correlator identifies an OpenTelemetry log with ERROR severity
- **What to do:** Open the UI Console and check the latest trace analyses for root cause details provided by the LLM

**AnalysisCompleted** (severity: `info`)

Fires whenever the analyzer finishes an LLM root cause analysis for a detected error. This is an informational alert confirming that the pipeline is working end-to-end: errors are being detected, correlated, sent to the LLM, and results are available in the UI Console.

- **Expression:** `increase(analyzer_analyses_completed_total[1m]) > 0`
- **Source metric:** `analyzer_analyses_completed_total` — a counter incremented each time the analyzer receives a successful response from the LLM
- **What to do:** Open the UI Console to review the new analysis results

## Verify monitoring resources

```bash
# Check ServiceMonitors
oc get servicemonitor -l app.kubernetes.io/part-of=smart-log-analyzer

# Check PrometheusRule
oc get prometheusrule smart-log-analyzer

# Check alert state
oc get prometheusrule smart-log-analyzer -o jsonpath='{.spec.groups[0].rules[*].alert}'
```
