# Manual Deployment Guide

This guide covers the step-by-step manual deployment of the Smart Telemetry Pipeline. For an automated installation, use `./create.sh` as described in the [main README](README.md#quick-start).

## Table of contents

1. [Deploy the Infrastructure](#deploy-the-infrastructure)
2. [Configure OpenAI Credentials](#configure-openai-credentials)
3. [Build Application Images](#build-application-images)
4. [Deploy Applications with Helm](#deploy-applications-with-helm)
5. [Delete](#delete)

## Deploy the Infrastructure

Only OpenShift Pipelines (Tekton) is pre-installed in the Developer Sandbox. Other operators (Data Grid, AMQ Broker, AMQ Streams) cannot be installed due to sandbox restrictions on cluster-scoped resources, so all infrastructure components are deployed as plain containers.

### Apply secrets and ConfigMaps

```bash
oc apply -f deploy/resources/secrets/
oc apply -f deploy/resources/configmaps/
```

### Deploy the OpenTelemetry infrastructure (Kafka + OTel Collector)

Deploy Kafka and an OpenTelemetry Collector that receives OTLP logs and traces and exports them to Kafka.

**Deploy Kafka:**

```bash
oc apply -f deploy/resources/otel-infra/kafka/kafka-sandbox.yaml
```

**Deploy the OpenTelemetry Collector via Helm:**

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm install camel-otel-collector open-telemetry/opentelemetry-collector \
  -f deploy/resources/otel-infra/otel-collector/values-sandbox.yaml \
  -n "${NS}" --wait --timeout 300s
```

### Deploy Infinispan (Data Grid)

```bash
oc apply -f deploy/resources/infinispan/infinispan-sandbox.yaml

# Wait for it to be ready
oc wait deployment/infinispan --for=condition=Available --timeout=180s
```

Create the caches (wait for the REST API to be ready first — it may take a few seconds after the pod starts):

```bash
ISPN_POD=$(oc get pod -l app=infinispan -o jsonpath='{.items[0].metadata.name}')

# Wait for Infinispan REST API
until oc exec "${ISPN_POD}" -- curl -sf -u admin:password --digest \
  http://localhost:11222/rest/v2/cache-managers/default/health/status 2>/dev/null; do
  sleep 3
done

for CACHE_FILE in deploy/resources/infinispan/caches/*.json; do
  CACHE_NAME=$(basename "${CACHE_FILE}" .json)
  echo "Creating cache '${CACHE_NAME}'..."
  oc exec "${ISPN_POD}" -- curl -s \
    -u admin:password --digest \
    -X POST "http://localhost:11222/rest/v2/caches/${CACHE_NAME}" \
    -H 'Content-Type: application/json' \
    -d "$(cat "${CACHE_FILE}")"
  echo ""
done
```

### Deploy AMQ Broker

```bash
oc apply -f deploy/resources/amq-broker/artemis-sandbox.yaml

# Wait for it to be ready
oc wait deployment/artemis --for=condition=Available --timeout=180s
```

### Create infra-endpoints ConfigMap

```bash
oc create configmap infra-endpoints \
  --from-literal=ARTEMIS_BROKER_URL="tcp://artemis.${NS}.svc:61616" \
  --from-literal=INFINISPAN_HOSTS="infinispan.${NS}.svc:11222" \
  --dry-run=client -o yaml | oc apply -f -
```

## Configure OpenAI Credentials

The analyzer component requires access to an OpenAI-compatible API for root cause analysis. The default credentials in `deploy/resources/secrets/openai.yaml` point to a local Ollama instance.

### Using OpenShift AI models on Developer Sandbox

The Developer Sandbox provides shared LLM inference services (e.g. Granite) in the `sandbox-shared-models` namespace. These endpoints use the OpenShift service serving CA for TLS and require an OpenShift authentication token.

**1. Identify the model endpoint:**

List the available inference services:

```bash
oc get inferenceservice -n sandbox-shared-models
```

The endpoint URL follows the pattern:
`https://<service-name>-predictor.sandbox-shared-models.svc.cluster.local:8443/v1`

**2. Create the secret with a ServiceAccount token:**

The model endpoint requires an OpenShift authentication token instead of a traditional API key. Generate a long-lived token from your namespace's `default` ServiceAccount:

```bash
SA_TOKEN=$(oc create token default --duration=120h)

oc create secret generic openai \
  --from-literal=OPENAI_API_KEY="${SA_TOKEN}" \
  --from-literal=OPENAI_BASE_URL="https://isvc-granite-31-8b-fp8-predictor.sandbox-shared-models.svc.cluster.local:8443/v1" \
  --from-literal=OPENAI_MODEL="isvc-granite-31-8b-fp8" \
  --dry-run=client -o yaml | oc apply -f -
```

> **Note:** The token expires after the specified duration (5 days in this example). Regenerate it and update the secret when it expires.

**3. Trust the OpenShift service CA:**

The model endpoint uses a TLS certificate signed by the OpenShift service serving CA, which is not in the default JVM truststore. Create a ConfigMap with the `inject-cabundle` annotation -- OpenShift automatically populates it with the service CA certificate. The Helm chart handles the rest (an init container builds a JVM truststore from the injected CA at pod startup).

```bash
oc create configmap service-ca-bundle
oc annotate configmap service-ca-bundle \
  service.beta.openshift.io/inject-cabundle=true
```

> **Note:** This ConfigMap must be created **before** installing the Helm chart. The analyzer deployment references it via the `serviceCa` configuration in `values.yaml`.

### Using an external OpenAI-compatible API

For external providers (OpenAI, Ollama, etc.) that use publicly trusted TLS certificates, only the secret is needed -- no truststore configuration:

```bash
oc create secret generic openai \
  --from-literal=OPENAI_API_KEY="<your-api-key>" \
  --from-literal=OPENAI_BASE_URL="https://api.openai.com/v1" \
  --from-literal=OPENAI_MODEL="gpt-4o-mini" \
  --dry-run=client -o yaml | oc apply -f -
```

## Build Application Images

Apply the Tekton tasks and pipeline:

```bash
oc apply -f deploy/tasks/
oc apply -f deploy/pipeline/
```

Build all three components (correlator, analyzer, ui-console) with a single pipeline:

```bash
cat > /tmp/workspace-template.yaml <<'EOF'
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

tkn pipeline start build-apps \
  -p namespace="${NS}" \
  --use-param-defaults \
  -w name=shared-workspace,volumeClaimTemplateFile=/tmp/workspace-template.yaml \
  --showlog
```

The `build-apps` pipeline first builds the `camel-launcher` image internally (downloading the JAR from Maven Central or Red Hat GA repository), then starts three parallel `build` pipeline runs (one per component) and waits for all of them to complete. The `shared-workspace` provides a PVC for the camel-launcher build step. Use `--showlog` to follow the progress in real time.

> **Note:** The `namespace` parameter must match your sandbox namespace so that images are pushed to the correct ImageStream.

Optionally, clean up completed pipeline and task runs to free resources (the sandbox has a limit of 30 ReplicaSets):

```bash
oc delete pipelinerun.tekton.dev --all
oc delete taskrun.tekton.dev --all
oc get rs --no-headers | awk '$2==0 && $3==0 && $4==0 {print $1}' | xargs -r oc delete rs
```

## Deploy Applications with Helm

Deploy the Helm chart (the application images must be built before this step):

```bash
helm install smart-log-analyzer chart/ \
  --set namespace="${NS}" \
  -n "${NS}"
```

To upgrade after changes:

```bash
helm upgrade smart-log-analyzer chart/ \
  --set namespace="${NS}" \
  -n "${NS}"
```

## Delete

To remove everything:

```bash
# Uninstall the Helm release
helm uninstall smart-log-analyzer

# Delete infrastructure
helm uninstall camel-otel-collector --ignore-not-found
oc delete -f deploy/resources/otel-infra/kafka/kafka-sandbox.yaml --ignore-not-found
oc delete -f deploy/resources/infinispan/infinispan-sandbox.yaml --ignore-not-found
oc delete -f deploy/resources/amq-broker/artemis-sandbox.yaml --ignore-not-found

# Delete all pipeline resources
oc delete pipelinerun --all
oc delete taskrun --all
oc delete pipeline --all
oc delete task --all

# Delete built image streams
oc delete is correlator analyzer ui-console camel-launcher --ignore-not-found

# Delete remaining resources
oc delete configmap infra-endpoints otel-infra-endpoints base-image-config-quarkus service-ca-bundle --ignore-not-found
oc delete secret infra-accounts openai service-ca-truststore --ignore-not-found
```

Or use the cleanup script:

```bash
./delete.sh
```
