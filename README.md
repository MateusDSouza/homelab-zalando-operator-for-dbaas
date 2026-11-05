# Zalando Postgres Operator — hands-on lab

A local lab where I ran the [Zalando Postgres Operator](https://github.com/zalando/postgres-operator) (v2.0.1) on [kind](https://kind.sigs.k8s.io/) to learn how highly available Postgres works on Kubernetes, and what it takes to run it as a managed database service (DBaaS): Patroni failover, connection pooling with PgBouncer, day-2 operations, backups with point-in-time recovery, and monitoring.

I broke things on purpose and measured what a client sees. The notes in [`study-notes/`](study-notes/) are kept as I wrote them while learning, including the questions and wrong turns along the way.

## Key findings

### 1. Failover: what a client actually experiences

A client pod wrote one row every 200 ms through the `acid-demo` Service while I broke the cluster. Outage = time from the last successful write to the first successful write after it. Data loss was checked by comparing the client's last acknowledged write with the last row in the table (gap query in [failover_drills.md](study-notes/failover_drills.md)).

| Drill | Write outage | Data lost? | What I learned |
| --- | --- | --- | --- |
| Planned switchover (`patronictl switchover`) | 3.4–6.8 s (3 runs) | No | Pods are not restarted: Patroni moves the primary and the `spilo-role` label. Kubernetes barely notices |
| Primary pod deleted | ~2.4 s | No | On SIGTERM Patroni releases the leader lock itself, so a replica promotes immediately. The StatefulSet recreates the pod with the same name and disk, but a **new IP** |
| Primary's node frozen (`docker pause`) | ~36 s | Not verified | ~30 s waiting for the leader-lock TTL to expire + ~5 s of actual failover |

- **Unclean failures are dominated by the leader-lock TTL** (30 s), not by Postgres. A shorter TTL means faster failover but more false failovers on network blips.
- **After the node freeze, writes stuttered for a few seconds**: the frozen pod still carried the `master` label (nobody could remove it), so the Service briefly routed to two "masters" and some connections hung until timeout. Client timeouts matter as much as failover speed.
- **The leader lock is a ConfigMap** (operator v2 default). Reading it after the drill showed the TTL, the number of leader transitions and the replication-slot positions of every member.
- **My client lives on a node too.** My first node drill took down the wrong node and killed my own measuring pod.

### 2. Connection pooling (PgBouncer)

| Test | Clients | Result | Server connections | TPS | Avg latency |
| --- | --- | --- | --- | --- | --- |
| Direct to Postgres (`max_connections=100`) | 150 | Fails at ~94 (last slots are reserved for superusers) | — | — | — |
| Through the operator's PgBouncer (transaction mode) | 150 | 0 failures | 30 (15 per pooler pod) | ~813 | ~185 ms |

Little's law: 150 clients / 813 TPS ≈ 185 ms, while each transaction spends only ~37 ms in Postgres. The rest is queueing in PgBouncer, so nothing fails but everyone waits. Postgres never sees the 150 clients, only the two pooler pods. Details in [connection_pooler_pgbouncer.md](study-notes/connection_pooler_pgbouncer.md).

### 3. Backups and point-in-time recovery

- WAL-G ships inside the Spilo image. The operator only passes configuration (bucket, credentials, schedule) through a pod-environment ConfigMap ([pod-env.yaml](lab-manifests/pod-env.yaml)).
- I took base backups into a local S3 store, then restored a **new cluster** to a timestamp using the source cluster's UID and a `clone` section. The restore starts from the latest base backup *before* the target time and replays WAL up to it. It took a few seconds on this tiny database; at scale RTO ≈ base backup download + WAL replay.
- **Supply-chain surprise:** MinIO's community images are no longer pullable from Docker Hub or anonymously from quay.io, so the lab broke mid-way. I switched to [Silo](https://github.com/pgsty/silo), a fork that keeps the S3 API, and WAL-G needed no change. A production platform should mirror and pin every image it depends on.

Details in [backups.md](study-notes/backups.md).

### 4. Day-2 operations and monitoring

- **Scaling 3 → 2 → 3:** the removed replica's PVC is retained, so the returning replica reattaches its disk and catches up from WAL. While it is gone, its replication slot holds WAL on the primary (the classic "disk full on the primary" risk). See [operations.md](study-notes/operations.md).
- **Monitoring sidecar (postgres_exporter):** adding it changes the pod template, which means a rolling update with a switchover. A crash-looping sidecar makes the whole pod NotReady, including the primary, and the operator injects superuser credentials the exporter doesn't need. See [monitoring.md](study-notes/monitoring.md).

### 5. A first Go client: `failover-probe`

The operator, Patroni's tooling and WAL-G are all written in Go, so I wrote a minimal Go client against the lab: [`failover-probe/`](failover-probe/) connects with [pgx](https://github.com/jackc/pgx), inserts one row with a 2-second deadline (`context.WithTimeout`) and prints the acknowledged row id (`INSERT … RETURNING id`). The deadline is what stops a client from hanging on a dead primary, and the returned id is the basis for proving that no acknowledged write is lost. Running it through `kubectl port-forward` also showed why port-forward is a debugging tool and not a measuring path: it exits whenever the pooler resets a connection. See [build_golang_tool.md](study-notes/build_golang_tool.md).

### 6. Thinking beyond the lab

How a fleet of thousands of instances could be run: several Kubernetes clusters to limit blast radius and API-server load, one operator per set of databases, namespaces per tenant (and why that is only a soft boundary), and why a database superuser is effectively a shell in the container. See [how_to_manage_in_prod.md](study-notes/how_to_manage_in_prod.md).

## Repository map

| Path | Contents |
| --- | --- |
| [`lab-manifests/`](lab-manifests/) | kind cluster, the `postgresql` cluster manifest (with exporter sidecar), the backup pod-environment ConfigMap |
| [`exploring_zalando_operator.md`](study-notes/exploring_zalando_operator.md) | Installing the operator, CRDs, the operator configuration, pooler modes, failsafe mode |
| [`deploying_instances.md`](study-notes/deploying_instances.md) | First 3-instance cluster and what the operator builds from it; operator vs Patroni responsibilities |
| [`connect_users_secrets.md`](study-notes/connect_users_secrets.md) | Users and secrets, connecting from a client pod, read-only replicas |
| [`failover_drills.md`](study-notes/failover_drills.md) | Switchover, pod delete and node failure drills, with measurements |
| [`connection_pooler_pgbouncer.md`](study-notes/connection_pooler_pgbouncer.md) | Enabling PgBouncer and load testing with pgbench |
| [`operations.md`](study-notes/operations.md) | Scaling and watching the operator reconcile |
| [`monitoring.md`](study-notes/monitoring.md) | Exporter sidecar and its trade-offs |
| [`backups.md`](study-notes/backups.md) | WAL-G, local S3 storage, point-in-time recovery |
| [`how_to_manage_in_prod.md`](study-notes/how_to_manage_in_prod.md) | Running this as a DBaaS at scale |
| [`build_golang_tool.md`](study-notes/build_golang_tool.md) | Reading the operator's Go code; running the Go probe |
| [`failover-probe/`](failover-probe/) | Go client that writes one row and reports the acknowledged id |
| [`images/`](images/) | Screenshots referenced from the notes |

## Reproducing the lab

Requirements: Docker, kind, kubectl, helm, and Go for `failover-probe` (Homebrew on macOS).

```bash
kind create cluster --config lab-manifests/kind-config.yaml

git clone --depth 1 --branch v2.0.1 https://github.com/zalando/postgres-operator.git
helm install postgres-operator ./postgres-operator/charts/postgres-operator \
  -n postgres-operator --create-namespace

kubectl apply -f lab-manifests/acid-demo.yaml
kubectl get postgresql acid-demo -w
```

Passwords are generated by the operator and stored in Kubernetes Secrets, e.g.:

```bash
kubectl get secret app-owner.acid-demo.credentials.postgresql.acid.zalan.do \
  -o jsonpath='{.data.password}' | base64 -d
```

## About credentials

Every credential in this repo (operator-generated passwords, `minioadmin`) belongs to a throwaway kind cluster that ran only on my laptop, was never reachable from outside, and has been deleted.

## The topics below were not covered because of lack of time

-  Turn `failover-probe` into a loop that runs as a pod in the cluster, reports outage windows and tracks every acknowledged id (replacing the shell write loop)
-  Verify data loss on unclean node failure, with and without Patroni synchronous mode
-  Prometheus + Thanos + Grafana on top of the exporter sidecar
-  GitOps for the platform layer (Argo CD)
