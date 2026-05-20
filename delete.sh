#!/bin/bash
set -e

echo "=== Cleaning Smart Telemetry Pipeline ==="

NS=$(oc project -q)
echo "Namespace: ${NS}"

echo ""
echo "--- Uninstalling Helm releases ---"
helm uninstall smart-log-analyzer 2>/dev/null || true
helm uninstall camel-otel-collector --ignore-not-found 2>/dev/null || true

echo ""
echo "--- Deleting infrastructure ---"
oc delete -f deploy/resources/otel-infra/kafka/kafka-sandbox.yaml --ignore-not-found 2>/dev/null || true
oc delete -f deploy/resources/infinispan/infinispan-sandbox.yaml --ignore-not-found 2>/dev/null || true
oc delete -f deploy/resources/amq-broker/artemis-sandbox.yaml --ignore-not-found 2>/dev/null || true

echo ""
echo "--- Deleting pipeline resources ---"
oc delete pipelinerun.tekton.dev --all 2>/dev/null || true
oc delete taskrun.tekton.dev --all 2>/dev/null || true
oc delete pipeline.tekton.dev --all 2>/dev/null || true
oc delete task.tekton.dev --all 2>/dev/null || true

echo ""
echo "--- Deleting built image streams ---"
oc delete is correlator analyzer ui-console camel-launcher --ignore-not-found 2>/dev/null || true

echo ""
echo "--- Deleting ConfigMaps and Secrets ---"
oc delete configmap infra-endpoints otel-infra-endpoints base-image-config-quarkus service-ca-bundle --ignore-not-found 2>/dev/null || true
oc delete secret infra-accounts openai service-ca-truststore --ignore-not-found 2>/dev/null || true

echo ""
echo "--- Deleting log-generator ---"
oc delete deployment log-generator --ignore-not-found 2>/dev/null || true
oc delete svc log-generator --ignore-not-found 2>/dev/null || true

echo ""
echo "--- Cleaning up empty ReplicaSets ---"
oc get rs --no-headers 2>/dev/null | awk '$2==0 && $3==0 && $4==0 {print $1}' | xargs -r oc delete rs 2>/dev/null || true

echo ""
echo "--- Waiting for pods to terminate ---"
oc wait pod --all --for=delete --timeout=120s 2>/dev/null || true

echo ""
echo "=== Cleanup complete ==="
oc get pods 2>/dev/null || true
