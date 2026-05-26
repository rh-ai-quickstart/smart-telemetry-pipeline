#!/bin/bash
set -e

echo "=== Installing Smart Telemetry Pipeline ==="

NS=$(oc project -q)
echo "Namespace: ${NS}"

# Step 1: Apply secrets and ConfigMaps
echo ""
echo "--- Applying secrets and ConfigMaps ---"
oc apply -f deploy/resources/secrets/
oc apply -f deploy/resources/configmaps/

# Step 2: Deploy Kafka
echo ""
echo "--- Deploying Kafka ---"
oc apply -f deploy/resources/otel-infra/kafka/kafka-sandbox.yaml
oc wait deployment/kafka --for=condition=Available --timeout=180s
echo "Kafka ready"

# Step 3: Deploy OTel Collector
echo ""
echo "--- Deploying OTel Collector ---"
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
helm repo update
helm install camel-otel-collector open-telemetry/opentelemetry-collector \
  -f deploy/resources/otel-infra/otel-collector/values-sandbox.yaml \
  -n "${NS}" --wait --timeout 300s
echo "OTel Collector ready"

# Step 4: Deploy Infinispan
echo ""
echo "--- Deploying Infinispan ---"
oc apply -f deploy/resources/infinispan/infinispan-sandbox.yaml
oc wait deployment/infinispan --for=condition=Available --timeout=180s
echo "Infinispan ready"

# Step 5: Create Infinispan caches
echo ""
echo "--- Creating Infinispan caches ---"
ISPN_POD=$(oc get pod -l app=infinispan -o jsonpath='{.items[0].metadata.name}')

# Wait for Infinispan REST API to be ready
for i in $(seq 1 30); do
  if oc exec "${ISPN_POD}" -- curl -sf -u admin:password --digest http://localhost:11222/rest/v2/caches >/dev/null 2>&1; then
    break
  fi
  echo "Waiting for Infinispan REST API..."
  sleep 2
done

for CACHE_FILE in deploy/resources/infinispan/caches/*.json; do
  CACHE_NAME=$(basename "${CACHE_FILE}" .json)
  echo "Creating cache '${CACHE_NAME}'..."
  oc exec "${ISPN_POD}" -- curl -sf \
    -u admin:password --digest \
    -X POST "http://localhost:11222/rest/v2/caches/${CACHE_NAME}" \
    -H 'Content-Type: application/json' \
    -d "$(cat "${CACHE_FILE}")"
done
echo "Caches created"

# Step 6: Deploy AMQ Broker
echo ""
echo "--- Deploying AMQ Broker ---"
oc apply -f deploy/resources/amq-broker/artemis-sandbox.yaml
oc wait deployment/artemis --for=condition=Available --timeout=180s
echo "AMQ Broker ready"

# Step 7: Create infra-endpoints ConfigMap
echo ""
echo "--- Creating infra-endpoints ConfigMap ---"
oc create configmap infra-endpoints \
  --from-literal=ARTEMIS_BROKER_URL="tcp://artemis.${NS}.svc:61616" \
  --from-literal=INFINISPAN_HOSTS="infinispan.${NS}.svc:11222" \
  --dry-run=client -o yaml | oc apply -f -

# Step 8: Configure OpenAI credentials
echo ""
echo "--- Configuring OpenAI credentials ---"
MODEL_NAME=$(oc get inferenceservice -n sandbox-shared-models -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep granite | head -1)
if [ -z "${MODEL_NAME}" ]; then
  echo "ERROR: No Granite model found in sandbox-shared-models namespace"
  exit 1
fi
echo "Using model: ${MODEL_NAME}"
SA_TOKEN=$(oc create token default --duration=120h)
oc create secret generic openai \
  --from-literal=OPENAI_API_KEY="${SA_TOKEN}" \
  --from-literal=OPENAI_BASE_URL="https://${MODEL_NAME}-predictor.sandbox-shared-models.svc.cluster.local:8443/v1" \
  --from-literal=OPENAI_MODEL="${MODEL_NAME}" \
  --dry-run=client -o yaml | oc apply -f -
echo "OpenAI credentials configured"

# Step 9: Create service CA bundle
echo ""
echo "--- Creating service CA bundle ---"
oc create configmap service-ca-bundle --dry-run=client -o yaml | oc apply -f -
oc annotate configmap service-ca-bundle service.beta.openshift.io/inject-cabundle=true --overwrite
echo "Service CA bundle configured"

# Step 10: Apply Tekton tasks and pipeline
echo ""
echo "--- Applying Tekton tasks and pipeline ---"
oc apply -f deploy/tasks/
oc apply -f deploy/pipeline/

# Step 11: Build application images
echo ""
echo "--- Building application images ---"
WORKSPACE_TEMPLATE=$(mktemp --suffix=.yaml)
cat > "${WORKSPACE_TEMPLATE}" <<'EOF'
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
  -w name=shared-workspace,volumeClaimTemplateFile="${WORKSPACE_TEMPLATE}" \
  --showlog
rm -f "${WORKSPACE_TEMPLATE}"

# Step 12: Deploy applications with Helm
echo ""
echo "--- Deploying applications with Helm ---"
helm install smart-log-analyzer chart/ \
  --set namespace="${NS}" \
  -n "${NS}"

# Step 13: Wait for all deployments to be ready
echo ""
echo "--- Waiting for application deployments ---"
for APP in correlator analyzer ui-console; do
  echo "Waiting for ${APP}..."
  oc wait deployment/"${APP}" --for=condition=Available --timeout=300s
done
echo "All applications ready"

# Step 14: Clean up build resources
echo ""
echo "--- Cleaning up build resources ---"
oc delete pipelinerun --all 2>/dev/null || true
oc delete taskrun --all 2>/dev/null || true
oc get rs --no-headers | awk '$2==0 && $3==0 && $4==0 {print $1}' | xargs -r oc delete rs 2>/dev/null || true

echo ""
echo "=== Installation complete ==="
oc get pods -l 'app in (kafka,infinispan,artemis,correlator,analyzer,ui-console)'
echo ""
ROUTE=$(oc get route ui-console -o jsonpath='https://{.spec.host}' 2>/dev/null)
if [ -n "${ROUTE}" ]; then
  echo "UI Console: ${ROUTE}"
fi
