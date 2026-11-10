# 05 - High Availability & Failover Drills

This runbook guides you through conducting automated failover drills against the Zalando PostgreSQL cluster. You will run continuous write probes, simulate primary pod crashes and node failures, measure Recovery Time Objective (RTO), and verify zero data loss (RPO = 0).

## Prerequisites

- Running `acid-demo` 3-instance PostgreSQL cluster.
- In-cluster client pod `pgclient` ready.
- Administrative access to Kubernetes cluster and Docker host.

---

## Step 1: Initialize Probe Schema in Database

Create a `ticks` table to record continuous timestamped write transactions from the probe client.

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
TRUNCATE ticks;
EOF
```

---

## Step 2: Start Continuous Write Probe Loop (Background / Terminal 1)

This loop submits an `INSERT` statement every 200ms. Keep this running or run it in a separate terminal during failover experiments to capture downtime.

```bash
export NAMESPACE="default"
export CLIENT_POD="pgclient"
export CLUSTER_NAME="acid-demo"
export APP_OWNER_PASSWORD=$(kubectl get secret "app-owner.${CLUSTER_NAME}.credentials.postgresql.acid.zalan.do" \
  -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

echo "Starting write probe loop (press Ctrl+C to stop)..."
kubectl exec -i "${CLIENT_POD}" -n "${NAMESPACE}" -- bash -c "
export PGPASSWORD='${APP_OWNER_PASSWORD}'
while true; do
  if psql 'host=${CLUSTER_NAME} user=app_owner dbname=appdb sslmode=require connect_timeout=1' \
     -qc 'INSERT INTO ticks DEFAULT VALUES' 2>/dev/null; then
    echo \"\$(date +%T.%N | cut -c1-12) OK\"
  else
    echo \"\$(date +%T.%N | cut -c1-12) FAIL\"
  fi
  sleep 0.2
done"
```

---

## Step 3: Monitor Spilo Pod Roles in Real Time (Terminal 2)

Monitor pod role transitions (`master` -> `replica`) in real time.

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"

kubectl get pods -n "${NAMESPACE}" -l cluster-name="${CLUSTER_NAME}" -L spilo-role -w
```

---

## Step 4: Failover Drill 1 - Primary Pod Crash

Simulate an abrupt termination of the active primary pod. Kubernetes will restart the pod, but Patroni will immediately promote an existing replica as the new leader.

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"

# Identify the current master pod
export CURRENT_MASTER=$(kubectl get pod -n "${NAMESPACE}" -l cluster-name="${CLUSTER_NAME}",spilo-role=master -o jsonpath='{.items[0].metadata.name}')
echo "Current Master Pod: ${CURRENT_MASTER}"

# Delete the master pod abruptly
kubectl delete pod "${CURRENT_MASTER}" -n "${NAMESPACE}" --now
```

### Verification: Confirm New Master Elected

Confirm that another pod assumed the master role and the old master rejoined as a replica once restarted.

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"

kubectl get pods -n "${NAMESPACE}" -l cluster-name="${CLUSTER_NAME}" -L spilo-role -o wide
```

---

## Step 5: Failover Drill 2 - Node Failure Simulation

Simulate a complete node outage where the host running the primary PostgreSQL pod becomes unreachable. Docker pause simulates network/hardware partition.

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"

# Find node hosting current master
export MASTER_NODE=$(kubectl get pod -n "${NAMESPACE}" -l cluster-name="${CLUSTER_NAME}",spilo-role=master -o jsonpath='{.items[0].spec.nodeName}')
echo "Master pod is on node: ${MASTER_NODE}"

# Pause the docker container corresponding to this Kind worker node
docker pause "${MASTER_NODE}"

echo "Node ${MASTER_NODE} paused. Waiting for Patroni lease TTL expiration (~30-35s)..."
sleep 40

# Unpause node to restore cluster health
docker unpause "${MASTER_NODE}"
echo "Node ${MASTER_NODE} resumed."
```

---

## Step 6: Verify Recovery & Inspect Data Loss (RPO)

Query the `ticks` table to calculate any discontinuity or data gap longer than 1 second across the failover event.

```bash
export NAMESPACE="default"
export CLIENT_POD="pgclient"
export CLUSTER_NAME="acid-demo"
export APP_OWNER_PASSWORD=$(kubectl get secret "app-owner.${CLUSTER_NAME}.credentials.postgresql.acid.zalan.do" \
  -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

kubectl exec -i "${CLIENT_POD}" -n "${NAMESPACE}" -- env PGPASSWORD="${APP_OWNER_PASSWORD}" \
  psql "host=${CLUSTER_NAME} user=app_owner dbname=appdb sslmode=require" \
  -c "
SELECT last_before, resumed_at, gap
FROM (
  SELECT lag(ts) OVER (ORDER BY id) AS last_before,
         ts AS resumed_at,
         ts - lag(ts) OVER (ORDER BY id) AS gap
  FROM ticks
) g
WHERE gap > interval '1 second'
ORDER BY resumed_at;"
```

---

## Step 7: Inspect Patroni DCS Leader Lock & Transitions

Inspect the Patroni Distributed Consensus Store (DCS) ConfigMap to observe the active leader, lease renewal time, and total failover transitions.

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"

kubectl get cm "${CLUSTER_NAME}-leader" -n "${NAMESPACE}" -o yaml
```
