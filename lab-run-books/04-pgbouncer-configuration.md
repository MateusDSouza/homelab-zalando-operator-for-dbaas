# 04 - PgBouncer Connection Pooler & Load Testing

This runbook covers enabling PgBouncer connection pooling for the PostgreSQL cluster, verifying pooler deployment and services, and running concurrency benchmarks using `pgbench` to observe transaction-mode connection multiplexing.

## Prerequisites

- Running `acid-demo` PostgreSQL cluster.
- `pgclient` pod ready in the `default` namespace.
- Working knowledge of transaction vs session pooling.

---

## Step 1: Enable PgBouncer Connection Pooler

Patch the `acid-demo` PostgreSQL custom resource to enable the connection pooler. The Zalando operator will deploy PgBouncer instances according to the operator configuration.

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"

kubectl patch postgresql "${CLUSTER_NAME}" -n "${NAMESPACE}" --type merge \
  -p '{"spec":{"enableConnectionPooler":true}}'
```

### Verification: Wait for Pooler Deployment and Services

Verify that the operator created the pooler Deployment and corresponding master/replica pooler Services.

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"

# Wait for pooler deployment rollout
kubectl rollout status deployment/"${CLUSTER_NAME}-pooler" -n "${NAMESPACE}" --timeout=120s

# Check created pooler services and deployments
kubectl get deploy,svc -n "${NAMESPACE}" -l cluster-name="${CLUSTER_NAME}" | grep pooler
```

---

## Step 2: Initialize pgbench Schema

Initialize the benchmark database schema with a scale factor of 10 inside `appdb` using the `pgclient` pod.

```bash
export NAMESPACE="default"
export CLIENT_POD="pgclient"
export CLUSTER_NAME="acid-demo"
export APP_OWNER_PASSWORD=$(kubectl get secret "app-owner.${CLUSTER_NAME}.credentials.postgresql.acid.zalan.do" \
  -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

echo "Initializing pgbench schema (Scale Factor: 10)..."
kubectl exec -i "${CLIENT_POD}" -n "${NAMESPACE}" -- env PGPASSWORD="${APP_OWNER_PASSWORD}" PGSSLMODE=require \
  pgbench -h "${CLUSTER_NAME}" -U app_owner -i -s 10 appdb
```

### Verification: Verify Benchmark Tables

Ensure standard pgbench tables (`pgbench_accounts`, `pgbench_branches`, `pgbench_history`, `pgbench_tellers`) are populated.

```bash
export NAMESPACE="default"
export CLIENT_POD="pgclient"
export CLUSTER_NAME="acid-demo"
export APP_OWNER_PASSWORD=$(kubectl get secret "app-owner.${CLUSTER_NAME}.credentials.postgresql.acid.zalan.do" \
  -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

kubectl exec -i "${CLIENT_POD}" -n "${NAMESPACE}" -- env PGPASSWORD="${APP_OWNER_PASSWORD}" PGSSLMODE=require \
  psql -h "${CLUSTER_NAME}" -U app_owner -d appdb -c "\dt"
```

---

## Step 3: Run Concurrent Load Benchmark Through PgBouncer

Execute a 30-second benchmark with 50 concurrent clients through the PgBouncer pooler service (`acid-demo-pooler`).

```bash
export NAMESPACE="default"
export CLIENT_POD="pgclient"
export CLUSTER_NAME="acid-demo"
export POOLER_HOST="${CLUSTER_NAME}-pooler"
export APP_OWNER_PASSWORD=$(kubectl get secret "app-owner.${CLUSTER_NAME}.credentials.postgresql.acid.zalan.do" \
  -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

echo "Running pgbench load test against pooler: ${POOLER_HOST}..."
kubectl exec -i "${CLIENT_POD}" -n "${NAMESPACE}" -- env PGPASSWORD="${APP_OWNER_PASSWORD}" PGSSLMODE=require \
  pgbench -h "${POOLER_HOST}" -p 5432 -U app_owner -c 50 -j 2 -T 30 -P 5 appdb
```

---

## Step 4: Monitor Active Connections in PostgreSQL

Observe how PgBouncer in transaction mode multiplexes client requests into a small, bounded set of backend server connections.

```bash
export NAMESPACE="default"
export CLIENT_POD="pgclient"
export CLUSTER_NAME="acid-demo"
export APP_OWNER_PASSWORD=$(kubectl get secret "app-owner.${CLUSTER_NAME}.credentials.postgresql.acid.zalan.do" \
  -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

kubectl exec -i "${CLIENT_POD}" -n "${NAMESPACE}" -- env PGPASSWORD="${APP_OWNER_PASSWORD}" PGSSLMODE=require \
  psql -h "${CLUSTER_NAME}" -U app_owner -d postgres -c "
SELECT usename, client_addr, state, count(*)
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY 1, 2, 3
ORDER BY 4 DESC;"
```
