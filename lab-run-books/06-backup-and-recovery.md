# 06 - Backup & Point-In-Time Recovery (WAL-G & MinIO)

This runbook guides you through deploying a local S3-compatible MinIO object store, configuring the Zalando PostgreSQL Operator to inject WAL-G backup configuration into Spilo pods, and taking and listing database backups.

## Prerequisites

- Running Kubernetes cluster with Zalando PostgreSQL Operator.
- Running `acid-demo` PostgreSQL cluster in the `default` namespace.
- Helm CLI installed.

---

## Step 1: Deploy MinIO S3-Compatible Storage

Deploy a local MinIO instance in the `default` namespace to act as an S3 object storage endpoint for Postgres WAL and base backups.

```bash
export NAMESPACE="default"

# Deploy MinIO server
kubectl create deployment minio -n "${NAMESPACE}" \
  --image=quay.io/minio/minio:latest -- \
  server /data --console-address :9001

# Configure credentials
kubectl set env deployment/minio -n "${NAMESPACE}" \
  MINIO_ROOT_USER=minioadmin \
  MINIO_ROOT_PASSWORD=minioadmin

# Expose MinIO service on port 9000
kubectl expose deployment minio -n "${NAMESPACE}" --port=9000 --target-port=9000 || true
```

### Verification: Wait for MinIO Pod Readiness

```bash
export NAMESPACE="default"

kubectl rollout status deployment/minio -n "${NAMESPACE}" --timeout=120s
kubectl get svc minio -n "${NAMESPACE}"
```

---

## Step 2: Create S3 Backup Bucket (`pg-backups`)

Create the target storage bucket named `pg-backups` using the MinIO CLI (`mc`) inside the MinIO pod or via a temporary pod.

```bash
export NAMESPACE="default"
export MINIO_POD=$(kubectl get pod -n "${NAMESPACE}" -l app=minio -o jsonpath='{.items[0].metadata.name}')

kubectl exec "${MINIO_POD}" -n "${NAMESPACE}" -- sh -c '
mc alias set local http://localhost:9000 minioadmin minioadmin
mc mb --ignore-existing local/pg-backups
mc ls local
'
```

---

## Step 3: Apply Pod Environment ConfigMap

Apply the configuration overrides defined in `lab-manifests/pod-env.yaml` to provide WAL-G credentials and S3 endpoint details.

```bash
export NAMESPACE="default"
export MANIFEST="lab-manifests/pod-env.yaml"

kubectl apply -n "${NAMESPACE}" -f "${MANIFEST}"
```

### Verification: Verify ConfigMap

```bash
export NAMESPACE="default"

kubectl get configmap pod-env-overrides -n "${NAMESPACE}" -o yaml
```

---

## Step 4: Configure Operator to Inject Pod Environment

Upgrade the Postgres Operator Helm release to register the environment ConfigMap and target S3 bucket.

```bash
export OPERATOR_NAMESPACE="postgres-operator"
export RELEASE_NAME="postgres-operator"
export CHART_PATH="./postgres-operator/charts/postgres-operator"

helm upgrade "${RELEASE_NAME}" "${CHART_PATH}" \
  -n "${OPERATOR_NAMESPACE}" \
  --reuse-values \
  --set configKubernetes.pod_environment_configmap=default/pod-env-overrides \
  --set configAwsOrGcp.wal_s3_bucket=pg-backups
```

### Verification: Observe Rolling Update on Cluster Pods

The operator detects the configuration change and initiates a rolling update of the cluster pods to inject the new environment variables into Spilo.

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"

kubectl rollout status statefulset/"${CLUSTER_NAME}" -n "${NAMESPACE}" --timeout=300s
```

---

## Step 5: Trigger Manual WAL-G Base Backup

Trigger a full WAL-G database backup from the active primary pod.

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"
export MASTER_POD=$(kubectl get pod -n "${NAMESPACE}" -l cluster-name="${CLUSTER_NAME}",spilo-role=master -o jsonpath='{.items[0].metadata.name}')

echo "Executing manual backup on primary pod: ${MASTER_POD}"
kubectl exec -i -n "${NAMESPACE}" "${MASTER_POD}" -c postgres -- su postgres -c \
  "envdir /run/etc/wal-e.d/env /scripts/postgres_backup.sh /home/postgres/pgdata/pgroot/data"
```

---

## Step 6: Verify and List Backups

Query WAL-G to verify that the backup snapshot was successfully uploaded to MinIO.

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"
export MASTER_POD=$(kubectl get pod -n "${NAMESPACE}" -l cluster-name="${CLUSTER_NAME}",spilo-role=master -o jsonpath='{.items[0].metadata.name}')

echo "Listing WAL-G backups from pod: ${MASTER_POD}"
kubectl exec -i -n "${NAMESPACE}" "${MASTER_POD}" -c postgres -- su postgres -c \
  "envdir /run/etc/wal-e.d/env wal-g backup-list"
```
