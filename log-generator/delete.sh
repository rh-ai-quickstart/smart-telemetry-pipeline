#!/bin/bash
set -e

echo "=== Removing Log Generator ==="

NS=$(oc project -q)
echo "Namespace: ${NS}"

echo ""
echo "--- Deleting deployment ---"
oc delete deployment log-generator --ignore-not-found 2>/dev/null || true

echo ""
echo "--- Deleting image stream ---"
oc delete is log-generator --ignore-not-found 2>/dev/null || true

echo ""
echo "--- Deleting pipeline ---"
oc delete pipeline deploy-log-generator --ignore-not-found 2>/dev/null || true

echo ""
echo "--- Cleaning up pipeline runs ---"
oc delete pipelinerun -l tekton.dev/pipeline=deploy-log-generator --ignore-not-found 2>/dev/null || true

echo ""
echo "--- Cleaning up empty ReplicaSets ---"
oc get rs --no-headers 2>/dev/null | awk '$2==0 && $3==0 && $4==0 {print $1}' | grep log-generator | xargs -r oc delete rs 2>/dev/null || true

echo ""
echo "=== Log Generator removed ==="
