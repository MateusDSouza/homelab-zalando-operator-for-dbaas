# 08 - Custom Go Failover Probe Application

This runbook guides you through preparing and running the custom Golang database probe located in `failover-probe/`. You will port-forward the PgBouncer pooler service, extract credentials, set the connection DSN, and execute probe writes with timeout guarantees.

## Prerequisites

- Go 1.21+ installed on your workstation (`go version`).
- Running `acid-demo` PostgreSQL cluster and `acid-demo-pooler` service.
- Database `appdb` accessible with `app_owner` credentials.

---

## Step 1: Ensure Target Probe Table Exists

The probe writes directly into the `ticks` table in `appdb`. Verify or create the table using the `pgclient` pod.

```bash
export NAMESPACE="default"
export CLIENT_POD="pgclient"
export CLUSTER_NAME="acid-demo"
export APP_OWNER_PASSWORD=$(kubectl get secret "app-owner.${CLUSTER_NAME}.credentials.postgresql.acid.zalan.do" \
  -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

kubectl exec -i "${CLIENT_POD}" -n "${NAMESPACE}" -- env PGPASSWORD="${APP_OWNER_PASSWORD}" \
  psql "host=${CLUSTER_NAME} user=app_owner dbname=appdb sslmode=require" << 'EOF'
CREATE TABLE IF NOT EXISTS ticks (
  id serial PRIMARY KEY,
  ts timestamptz DEFAULT now()
);
EOF
```

---

## Step 2: Forward Connection Pooler Port to Workstation

Expose the PgBouncer pooler service locally on port `6432`. Run this command in a background or separate terminal session.

```bash
export NAMESPACE="default"
export SERVICE_NAME="acid-demo-pooler"
export LOCAL_PORT=6432
export REMOTE_PORT=5432

echo "Forwarding svc/${SERVICE_NAME} ${LOCAL_PORT}:${REMOTE_PORT} (Press Ctrl+C to stop)..."
kubectl port-forward -n "${NAMESPACE}" "svc/${SERVICE_NAME}" "${LOCAL_PORT}:${REMOTE_PORT}"
```

---

## Step 3: Run the Golang Probe Application

Extract the `app_owner` password, construct the `DATABASE_URL` connection string, and run the probe application to insert a tick record.

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"
export APPPASS=$(kubectl get secret "app-owner.${CLUSTER_NAME}.credentials.postgresql.acid.zalan.do" \
  -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

export DATABASE_URL="postgres://app_owner:${APPPASS}@localhost:6432/appdb?sslmode=require"

# Execute the Go probe
cd failover-probe && go run .
```

### Verification: Confirm Inserted Record in PostgreSQL

Query the `ticks` table to confirm that the newly inserted row ID from the probe output is persisted in the database.

```bash
export NAMESPACE="default"
export CLIENT_POD="pgclient"
export CLUSTER_NAME="acid-demo"
export APP_OWNER_PASSWORD=$(kubectl get secret "app-owner.${CLUSTER_NAME}.credentials.postgresql.acid.zalan.do" \
  -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

kubectl exec -i "${CLIENT_POD}" -n "${NAMESPACE}" -- env PGPASSWORD="${APP_OWNER_PASSWORD}" \
  psql "host=${CLUSTER_NAME} user=app_owner dbname=appdb sslmode=require" \
  -c "SELECT id, ts FROM ticks ORDER BY id DESC LIMIT 5;"
```
