# Zalando Postgres Operator lab on kind.
# Start: `just up`   Drills: `just drills`   Stop: `just down`   Menu: `just --choose`

set shell := ["bash", "-euo", "pipefail", "-c"]

kind_name        := "pg-lab"                      # matches name: in kind-config.yaml
cluster          := env("CLUSTER", "acid-demo")   # matches metadata.name in acid-demo.yaml
ns               := env("NAMESPACE", "default")
operator_version := "v2.0.1"
manifests        := "lab-manifests"
app_secret       := "app-owner." + cluster + ".credentials.postgresql.acid.zalan.do"

default:
    @just --list

# ---------- lifecycle ----------

# Create everything: kind cluster, operator, Postgres cluster, client pod
up: cluster-create operator-install pg-create client-create
    @echo "Lab ready. Next: just status / just drills"

# kind cluster (1 control plane + 3 workers)
cluster-create:
    kind get clusters | grep -qx {{kind_name}} || kind create cluster --config {{manifests}}/kind-config.yaml

# Zalando operator via Helm, from the pinned upstream tag
operator-install:
    [ -d postgres-operator ] || git clone --depth 1 --branch {{operator_version}} https://github.com/zalando/postgres-operator.git
    helm upgrade --install postgres-operator ./postgres-operator/charts/postgres-operator \
      -n postgres-operator --create-namespace --wait

# Postgres cluster from acid-demo.yaml, then wait until healthy
pg-create:
    kubectl apply -n {{ns}} -f {{manifests}}/acid-demo.yaml
    just wait-ready

# Client pod pinned to the control-plane node, so node drills never kill it
client-create:
    kubectl get pod pgclient -n {{ns}} >/dev/null 2>&1 || kubectl run pgclient -n {{ns}} --image=postgres:17 --restart=Never \
      --overrides='{"spec":{"nodeName":"{{kind_name}}-control-plane","tolerations":[{"operator":"Exists"}]}}' -- sleep infinity
    kubectl wait -n {{ns}} pod/pgclient --for=condition=Ready --timeout=3m
    kubectl exec -i -n {{ns}} pgclient -- bash -c 'cat > /tmp/loop.sh' < scripts/loop.sh

# Optional: local S3 (Silo) + WAL-G backups, as in backups.md
backups-up:
    kubectl get deploy minio -n {{ns}} >/dev/null 2>&1 || kubectl create deployment minio -n {{ns}} \
      --image=docker.io/pgsty/silo:RELEASE.2026-10-26T00-00-00Z -- silo server /data --console-address :9001
    kubectl set env deploy/minio -n {{ns}} MINIO_ROOT_USER=minioadmin MINIO_ROOT_PASSWORD=minioadmin
    kubectl get svc minio -n {{ns}} >/dev/null 2>&1 || kubectl expose deploy/minio -n {{ns}} --port 9000
    kubectl rollout status deploy/minio -n {{ns}} --timeout=3m
    kubectl exec -n {{ns}} deploy/minio -- sh -c 'mcli alias set local http://localhost:9000 minioadmin minioadmin && mcli mb --ignore-existing local/pg-backups'
    kubectl apply -f {{manifests}}/pod-env.yaml
    helm upgrade postgres-operator ./postgres-operator/charts/postgres-operator -n postgres-operator --reuse-values --wait \
      --set configKubernetes.pod_environment_configmap={{ns}}/pod-env-overrides \
      --set configAwsOrGcp.wal_s3_bucket=pg-backups

# Delete the whole lab
[confirm("Delete the whole kind lab cluster?")]
down:
    kind delete cluster --name {{kind_name}}

# ---------- inspect ----------

# Pods, roles, nodes and Patroni's view
status:
    kubectl get pods -n {{ns}} -l cluster-name={{cluster}} -L spilo-role -o wide
    kubectl exec -n {{ns}} "$(kubectl get pods -n {{ns}} -l cluster-name={{cluster}},spilo-role=master -o jsonpath='{.items[0].metadata.name}')" -c postgres -- patronictl list

# Current leader-lock holder and renew time
leader:
    kubectl get cm {{cluster}}-leader -n {{ns}} -o jsonpath='{.metadata.annotations.leader}{"  renewed: "}{.metadata.annotations.renewTime}{"\n"}'

# Interactive psql as app_owner, from inside the cluster
psql host=cluster:
    #!/usr/bin/env bash
    set -euo pipefail
    pass=$(kubectl get secret {{app_secret}} -n {{ns}} -o jsonpath='{.data.password}' | base64 -d)
    kubectl exec -it -n {{ns}} pgclient -- env PGPASSWORD="$pass" psql "host={{host}} user=app_owner dbname=appdb sslmode=require"

# Operator logs
operator-logs:
    kubectl -n postgres-operator logs deploy/postgres-operator -f --since=1m

# Wait until the cluster is Running and all its pods are Ready
wait-ready:
    kubectl wait -n {{ns}} postgresql/{{cluster}} --for=jsonpath='{.status.PostgresClusterStatus}'=Running --timeout=10m
    kubectl wait -n {{ns}} pod -l cluster-name={{cluster}} --for=condition=Ready --timeout=10m

# ---------- write probe ----------

# Start the write loop in the background (host: cluster, or <cluster>-pooler)
probe-start host=cluster:
    #!/usr/bin/env bash
    set -euo pipefail
    pass=$(kubectl get secret {{app_secret}} -n {{ns}} -o jsonpath='{.data.password}' | base64 -d)
    kubectl exec -n {{ns}} pgclient -- env PGPASSWORD="$pass" psql "host={{cluster}} user=app_owner dbname=appdb sslmode=require" \
      -qc "CREATE TABLE IF NOT EXISTS ticks (id serial, ts timestamptz default now());"
    just probe-stop
    kubectl exec -n {{ns}} pgclient -- env PGPASSWORD="$pass" bash -c \
      'setsid nohup bash /tmp/loop.sh {{host}} > /tmp/loop.log 2>&1 & echo $! > /tmp/loop.pid'
    echo "probe writing to {{host}} - follow it with: just probe-log"

# Follow the probe output (Ctrl+C stops watching, not the probe)
probe-log:
    kubectl exec -it -n {{ns}} pgclient -- tail -f /tmp/loop.log

# Stop the write loop
probe-stop:
    kubectl exec -n {{ns}} pgclient -- bash -c 'kill $(cat /tmp/loop.pid 2>/dev/null) 2>/dev/null || true'

# Every write gap over 1 s (outages, and times the probe was off)
report:
    #!/usr/bin/env bash
    set -euo pipefail
    pass=$(kubectl get secret {{app_secret}} -n {{ns}} -o jsonpath='{.data.password}' | base64 -d)
    kubectl exec -n {{ns}} pgclient -- env PGPASSWORD="$pass" psql "host={{cluster}} user=app_owner dbname=appdb sslmode=require" -c \
      "SELECT last_before, resumed_at, gap FROM (
         SELECT lag(ts) OVER (ORDER BY id) AS last_before, ts AS resumed_at, ts - lag(ts) OVER (ORDER BY id) AS gap
         FROM ticks) g
       WHERE gap > interval '1 second' ORDER BY resumed_at;"

# ---------- failover drills ----------

# Run all three drills with the probe on, then print the gaps
drills: probe-start
    just drill-switchover
    sleep 15
    just drill-pod-delete
    just wait-ready
    sleep 15
    just drill-node-pause
    just wait-ready
    sleep 5
    just probe-stop
    just report

# Drill 1: planned Patroni switchover
drill-switchover:
    #!/usr/bin/env bash
    set -euo pipefail
    old=$(kubectl get pods -n {{ns}} -l cluster-name={{cluster}},spilo-role=master -o jsonpath='{.items[0].metadata.name}')
    echo "$(date -u +%T) switchover away from $old"
    kubectl exec -n {{ns}} "$old" -c postgres -- patronictl switchover --force
    just wait-new-leader "$old"

# Drill 2: delete the primary pod
drill-pod-delete:
    #!/usr/bin/env bash
    set -euo pipefail
    old=$(kubectl get pods -n {{ns}} -l cluster-name={{cluster}},spilo-role=master -o jsonpath='{.items[0].metadata.name}')
    echo "$(date -u +%T) deleting primary pod $old"
    kubectl delete pod -n {{ns}} "$old" --wait=false
    just wait-new-leader "$old"

# Drill 3: freeze the primary's node (unclean failure), then unfreeze it
drill-node-pause:
    #!/usr/bin/env bash
    set -euo pipefail
    old=$(kubectl get pods -n {{ns}} -l cluster-name={{cluster}},spilo-role=master -o jsonpath='{.items[0].metadata.name}')
    node=$(kubectl get pod -n {{ns}} "$old" -o jsonpath='{.spec.nodeName}')   # kind node name = docker container name
    echo "$(date -u +%T) pausing node $node (primary $old)"
    docker pause "$node"
    trap 'docker unpause "$node" >/dev/null 2>&1 && echo "$(date -u +%T) node $node unpaused"' EXIT
    just wait-new-leader "$old" 180
    echo "keeping the node paused 10 s more to watch the stutter"
    sleep 10

# Poll the leader ConfigMap until someone other than <old> holds the lock
wait-new-leader old timeout="120":
    #!/usr/bin/env bash
    set -euo pipefail
    for i in $(seq {{timeout}}); do
      leader=$(kubectl get cm {{cluster}}-leader -n {{ns}} -o jsonpath='{.metadata.annotations.leader}' 2>/dev/null || true)
      if [ -n "$leader" ] && [ "$leader" != "{{old}}" ]; then
        echo "$(date -u +%T) new leader: $leader (after ~${i}s)"; exit 0
      fi
      sleep 1
    done
    echo "no new leader after {{timeout}}s"; exit 1
