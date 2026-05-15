#!/bin/bash
set -e

echo "=== Deploying Log Generator ==="

NS=$(oc project -q)
echo "Namespace: ${NS}"

# Apply the pipeline
echo ""
echo "--- Applying pipeline ---"
oc apply -f log-generator/pipeline.yaml

# Apply the PipelineRun (substitute namespace placeholder)
echo ""
echo "--- Starting pipeline ---"
sed "s/NAMESPACE/${NS}/g" log-generator/pipelinerun.yaml | oc apply -f -

tkn pipelinerun logs deploy-log-generator-run -f

# Clean up pipeline runs
echo ""
echo "--- Cleaning up pipeline runs ---"
oc delete pipelinerun deploy-log-generator-run --ignore-not-found 2>/dev/null || true
oc delete taskrun -l tekton.dev/pipelineRun=deploy-log-generator-run --ignore-not-found 2>/dev/null || true

echo ""
echo "=== Log Generator deployed ==="
oc get pods -l app=log-generator
