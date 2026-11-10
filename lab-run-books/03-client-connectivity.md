# 03 - Client Connectivity & RBAC Verification

This runbook guides you through deploying an in-cluster PostgreSQL client (`pgclient`), extracting generated user credentials from Kubernetes Secrets, and validating read-write access on the Primary service versus read-only enforcement on the Replica service.

## Prerequisites

- PostgreSQL cluster `acid-demo` running in the `default` namespace.
- `kubectl` configured with access to the cluster.

---

## Step 1: Deploy In-Cluster PostgreSQL Client Pod

Deploy a lightweight client pod running the official `postgres:17` image to execute `psql` commands inside the cluster network.

```bash
export NAMESPACE="default"
export CLIENT_POD="pgclient"

if kubectl get pod "${CLIENT_POD}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Pod ${CLIENT_POD} already exists."
else
  kubectl run "${CLIENT_POD}" -n "${NAMESPACE}" \
    --image=postgres:17 \
    --restart=Never \
    -- sleep infinity
fi
```

### Verification: Confirm Client Pod is Running

```bash
export NAMESPACE="default"
export CLIENT_POD="pgclient"

kubectl wait --for=condition=Ready pod/"${CLIENT_POD}" -n "${NAMESPACE}" --timeout=60s
```

---

## Step 2: Retrieve Credentials from Kubernetes Secrets

Extract and decode the randomly generated database passwords stored by the operator.

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"

# Extract superuser password
export POSTGRES_PASSWORD=$(kubectl get secret "postgres.${CLUSTER_NAME}.credentials.postgresql.acid.zalan.do" \
  -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

# Extract application owner password
export APP_OWNER_PASSWORD=$(kubectl get secret "app-owner.${CLUSTER_NAME}.credentials.postgresql.acid.zalan.do" \
  -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

echo "Postgres password retrieved: $(echo -n "${POSTGRES_PASSWORD}" | cut -c1-3)***"
echo "App Owner password retrieved: $(echo -n "${APP_OWNER_PASSWORD}" | cut -c1-3)***"
```

---

## Step 3: Connect to the Master Service and Test Write Access

Connect to the primary endpoint (`acid-demo`) through the client pod and create a test table.

```bash
export NAMESPACE="default"
export CLIENT_POD="pgclient"
export CLUSTER_NAME="acid-demo"
export APP_OWNER_PASSWORD=$(kubectl get secret "app-owner.${CLUSTER_NAME}.credentials.postgresql.acid.zalan.do" \
  -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

kubectl exec -i "${CLIENT_POD}" -n "${NAMESPACE}" -- env PGPASSWORD="${APP_OWNER_PASSWORD}" \
  psql "host=${CLUSTER_NAME} user=app_owner dbname=appdb sslmode=require" << 'EOF'
CREATE TABLE IF NOT EXISTS connectivity_test (
  id serial PRIMARY KEY,
  message text NOT NULL,
  created_at timestamptz DEFAULT now()
);

INSERT INTO connectivity_test (message) VALUES ('Write verified via primary service');
SELECT id, message, created_at FROM connectivity_test ORDER BY id DESC LIMIT 1;
EOF
```

### Verification: Confirm Master Status via SQL

Verify that the connection is active on the primary instance (`pg_is_in_recovery()` must return `false`).

```bash
export NAMESPACE="default"
export CLIENT_POD="pgclient"
export CLUSTER_NAME="acid-demo"
export APP_OWNER_PASSWORD=$(kubectl get secret "app-owner.${CLUSTER_NAME}.credentials.postgresql.acid.zalan.do" \
  -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

kubectl exec -i "${CLIENT_POD}" -n "${NAMESPACE}" -- env PGPASSWORD="${APP_OWNER_PASSWORD}" \
  psql "host=${CLUSTER_NAME} user=app_owner dbname=appdb sslmode=require" \
  -c "SELECT inet_server_addr(), pg_is_in_recovery() AS is_replica;"
```

---

## Step 4: Validate Read-Only Enforcement on Replica Service

Connect to the replica service endpoint (`acid-demo-repl`) to verify that queries can read data but write operations are strictly rejected.

```bash
export NAMESPACE="default"
export CLIENT_POD="pgclient"
export CLUSTER_NAME="acid-demo"
export APP_OWNER_PASSWORD=$(kubectl get secret "app-owner.${CLUSTER_NAME}.credentials.postgresql.acid.zalan.do" \
  -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

echo "=== Attempting read query on Replica ==="
kubectl exec -i "${CLIENT_POD}" -n "${NAMESPACE}" -- env PGPASSWORD="${APP_OWNER_PASSWORD}" \
  psql "host=${CLUSTER_NAME}-repl user=app_owner dbname=appdb sslmode=require" \
  -c "SELECT inet_server_addr(), pg_is_in_recovery() AS is_replica, count(*) FROM connectivity_test;"

echo "=== Attempting write query on Replica (Expected to fail) ==="
kubectl exec -i "${CLIENT_POD}" -n "${NAMESPACE}" -- env PGPASSWORD="${APP_OWNER_PASSWORD}" \
  psql "host=${CLUSTER_NAME}-repl user=app_owner dbname=appdb sslmode=require" \
  -c "INSERT INTO connectivity_test (message) VALUES ('Illegal replica write');" || echo "WRITE REJECTED AS EXPECTED"
```
