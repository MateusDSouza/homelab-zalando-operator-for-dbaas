# 07 - Observability & Prometheus Metrics Exporter Setup

This runbook covers configuring a Prometheus `postgres-exporter` sidecar container within each PostgreSQL pod, inspecting multi-container pod readiness, and verifying metrics scraping for database health and replication lag.

## Prerequisites

- Running Zalando PostgreSQL Operator.
- Working knowledge of Prometheus scraping and Kubernetes sidecar patterns.
- Manifest `lab-manifests/acid-demo.yaml` containing the sidecar configuration.

---

## Step 1: Apply Cluster Manifest with Exporter Sidecar

Ensure `lab-manifests/acid-demo.yaml` specifies the `exporter` sidecar container on port `9187` and apply the manifest.

```bash
export NAMESPACE="default"
export MANIFEST="lab-manifests/acid-demo.yaml"

kubectl apply -n "${NAMESPACE}" -f "${MANIFEST}"
```

### Verification: Confirm Multi-Container Pod Rollout (2/2 READY)

Verify that each pod in the cluster now runs 2 containers (`postgres` and `exporter`) and is in `Ready` status.

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"

# Wait for rolling update to complete
kubectl rollout status statefulset/"${CLUSTER_NAME}" -n "${NAMESPACE}" --timeout=300s

# Verify container counts
kubectl get pods -n "${NAMESPACE}" -l cluster-name="${CLUSTER_NAME}" \
  -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[*].ready,IMAGES:.spec.containers[*].name'
```

---

## Step 2: Inspect Exporter Sidecar Logs

Verify that the exporter sidecar successfully established a local connection to the Postgres process via localhost.

```bash
export NAMESPACE="default"
export TARGET_POD="acid-demo-0"

kubectl logs "${TARGET_POD}" -n "${NAMESPACE}" -c exporter --tail=30
```

---

## Step 3: Forward Exporter Metrics Port to Localhost

Port-forward the metrics port (`9187`) from the cluster primary pod to your local environment. Run this in a background or separate terminal session if using CLI directly.

```bash
export NAMESPACE="default"
export MASTER_POD=$(kubectl get pod -n "${NAMESPACE}" -l cluster-name=acid-demo,spilo-role=master -o jsonpath='{.items[0].metadata.name}')

echo "Starting port-forward for ${MASTER_POD}:9187 (Press Ctrl+C to stop)..."
kubectl port-forward "${MASTER_POD}" -n "${NAMESPACE}" 9187:9187
```

---

## Step 4: Verification: Scrape and Validate Core Prometheus Metrics

Fetch the metrics endpoint via `curl` and filter for critical database health, replication, and connection metrics.

```bash
export METRICS_URL="http://localhost:9187/metrics"

echo "=== Fetching Core PostgreSQL Metrics ==="
curl -s "${METRICS_URL}" | grep -E '^(pg_up|pg_stat_replication|pg_replication_lag|pg_stat_database_numbackends)'
```

### Verification Checkpoints:
- `pg_up 1`: Confirms the exporter can reach and query the local PostgreSQL daemon.
- `pg_stat_database_numbackends`: Tracks client connection volume.
- `pg_stat_replication`: Exposes active WAL sender threads streaming to read replicas.
