# 01 - Environment & Zalando Postgres Operator Setup

This runbook guides you through preparing your local development environment, creating a multi-node Kind cluster, and deploying the Zalando PostgreSQL Operator using Helm.

## Prerequisites

- macOS or Linux workstation with Homebrew installed.
- Docker running locally with at least 4 CPUs and 4GB memory allocated.
- Repository root directory as the current working directory.

---

## Step 1: Install Host CLI Tools

Ensure all necessary CLI tooling is installed on your workstation.

```bash
# Install required CLI tools
brew install --cask docker || true
brew install kind kubectl helm k9s postgresql@17
brew link --overwrite postgresql@17 || true
```

### Verification: Verify Installed CLI Tool Versions

```bash
docker version --format '{{.Client.Version}}'
kind version
kubectl version --client
helm version --short
psql --version
pgbench --version
```

---

## Step 2: Create Multi-Node Kind Cluster

Create a Kubernetes cluster with 1 control plane node and 3 worker nodes using `lab-manifests/kind-config.yaml`.

```bash
export CLUSTER_NAME="pg-lab"
export CONFIG_FILE="lab-manifests/kind-config.yaml"

if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster '${CLUSTER_NAME}' already exists. Skipping creation."
else
  kind create cluster --name "${CLUSTER_NAME}" --config "${CONFIG_FILE}"
fi
```

### Verification: Check Cluster Nodes

Ensure all 4 nodes (1 control-plane and 3 workers) are created and in `Ready` status.

```bash
kubectl get nodes -o wide
```

---

## Step 3: Install Zalando PostgreSQL Operator via Helm

Install the Zalando PostgreSQL Operator into the dedicated namespace `postgres-operator` using the chart located at `./postgres-operator/charts/postgres-operator`.

```bash
export OPERATOR_NAMESPACE="postgres-operator"
export RELEASE_NAME="postgres-operator"
export CHART_PATH="./postgres-operator/charts/postgres-operator"

helm upgrade --install "${RELEASE_NAME}" "${CHART_PATH}" \
  --namespace "${OPERATOR_NAMESPACE}" \
  --create-namespace
```

### Verification: Check Operator Pods and CRDs

Verify that the operator pod is running and the custom resource definitions (CRDs) are registered in the cluster.

```bash
export OPERATOR_NAMESPACE="postgres-operator"

# Wait for operator pod readiness
kubectl rollout status deployment/postgres-operator -n "${OPERATOR_NAMESPACE}" --timeout=120s

# Verify Custom Resource Definitions (CRDs)
kubectl get crd | grep 'acid.zalan.do'
```

---

## Step 4: Inspect Operator Configuration & Logs

Review the operator's active runtime configuration and inspect its reconcile event stream.

```bash
export OPERATOR_NAMESPACE="postgres-operator"

# Check active OperatorConfiguration
kubectl -n "${OPERATOR_NAMESPACE}" get operatorconfiguration -o yaml
```

```bash
export OPERATOR_NAMESPACE="postgres-operator"

# Inspect the operator's recent logs
kubectl -n "${OPERATOR_NAMESPACE}" logs deployment/postgres-operator --tail=50
```
