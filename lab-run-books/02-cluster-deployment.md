# 02 - PostgreSQL Cluster Deployment & Verification

This runbook covers deploying a highly available 3-node PostgreSQL cluster managed by the Zalando Operator using Patroni, inspecting the generated Kubernetes resources, and validating the leader/replica topology.

## Prerequisites

- A running Kubernetes cluster (e.g., `pg-lab` Kind cluster).
- Zalando PostgreSQL Operator installed and running in the `postgres-operator` namespace.
- Access to `lab-manifests/acid-demo.yaml`.

---

## Step 1: Deploy PostgreSQL Custom Resource

Apply the PostgreSQL cluster manifest to provision a 3-node PostgreSQL 17 cluster with persistent volumes and resource limits.

```bash
export NAMESPACE="default"
export MANIFEST="lab-manifests/acid-demo.yaml"

kubectl apply -n "${NAMESPACE}" -f "${MANIFEST}"
```

### Verification: Wait for Cluster Pods and Inspect Spilo Roles

Wait for all 3 cluster pods to transition to the `Running` state and inspect their designated Spilo roles (`master` vs `replica`).

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"

# Wait for StatefulSet rollout to complete
kubectl rollout status statefulset/"${CLUSTER_NAME}" -n "${NAMESPACE}" --timeout=300s

# Inspect pod status, IPs, and Spilo roles across worker nodes
kubectl get pods -n "${NAMESPACE}" -l cluster-name="${CLUSTER_NAME}" -L spilo-role -o wide
```

---

## Step 2: Inspect Created Kubernetes Resources

The operator automatically creates and manages StatefulSets, ClusterIP Services (one for master write traffic, one for replica read-only traffic), Secrets for defined users, and PodDisruptionBudgets.

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"

echo "=== StatefulSets, Services, Secrets, PDBs, and ConfigMaps ==="
kubectl get sts,svc,secret,pdb,cm -n "${NAMESPACE}" -l cluster-name="${CLUSTER_NAME}"
```

### Verification: Verify Generated Credentials

Confirm that the operator generated secrets for each user declared in the manifest (`postgres`, `app_owner`, `app_user`, and `standby`).

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"

kubectl get secrets -n "${NAMESPACE}" -l cluster-name="${CLUSTER_NAME}"
```

---

## Step 3: Inspect Patroni Cluster Topology

Patroni runs as the high-availability supervisor inside each Spilo container. Query `patronictl` to view leader status, WAL LSN coordinates, and replication lag.

```bash
export NAMESPACE="default"
export MASTER_POD=$(kubectl get pod -n "${NAMESPACE}" -l cluster-name=acid-demo,spilo-role=master -o jsonpath='{.items[0].metadata.name}')

echo "Querying Patroni topology from Leader pod: ${MASTER_POD}"
kubectl exec -it -n "${NAMESPACE}" "${MASTER_POD}" -c postgres -- patronictl list
```

---

## Step 4: Scale Cluster Instances (Day-2 Operation)

You can scale the cluster up or down dynamically by patching the `numberOfInstances` field in the PostgreSQL custom resource.

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"
export REPLICAS=2  # Change to 2 to scale down, or 3 to scale back up

kubectl patch postgresql "${CLUSTER_NAME}" -n "${NAMESPACE}" --type merge \
  -p "{\"spec\":{\"numberOfInstances\":${REPLICAS}}}"
```

### Verification: Confirm Topology After Scaling

```bash
export NAMESPACE="default"
export CLUSTER_NAME="acid-demo"

kubectl get pods -n "${NAMESPACE}" -l cluster-name="${CLUSTER_NAME}" -L spilo-role
```
