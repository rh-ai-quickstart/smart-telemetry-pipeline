# Troubleshooting

## Resource Quota Exceeded

The sandbox has CPU and memory quotas. If pods are stuck in `Pending`:

```bash
oc describe resourcequota
oc get pods -o custom-columns=NAME:.metadata.name,MEM:.spec.containers[0].resources.limits.memory
```

Reduce memory limits and re-deploy:

```bash
NS=$(oc project -q)
helm upgrade smart-log-analyzer chart/ \
  --set namespace="${NS}" \
  -n "${NS}"
```

## Pods Scaled Down After Inactivity

The sandbox may idle pods after a period of inactivity. Access the route or run `oc get pods` to wake them up. If pods don't restart:

```bash
oc rollout restart deployment correlator analyzer ui-console
```

## Pods CrashLooping with Missing Secrets

Ensure the required secrets exist:

```bash
oc get secret infra-accounts openai
```

If missing, re-apply them:

```bash
oc apply -f deploy/resources/secrets/
```

## Image Pull Errors

Make sure the build pipeline completed successfully and pushed the images:

```bash
oc get is
```

Each ImageStream (correlator, analyzer, ui-console) should have a `latest` tag.
