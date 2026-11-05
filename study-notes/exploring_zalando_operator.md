## Installing tools and the operator

```bash
brew install --cask docker
brew install kind kubectl helm k9s
#psql and pgbench 
brew install postgresql@17 && brew link postgresql@17
#check installation
docker version && kind version && kubectl version --client && helm version 
```

- Before moving to the operator we need to use kind, which is a kubernetes on top of docker - to create our k8s cluster. We have the manifest at @kind-config.yaml.

Use kind command, not kubectl.
```bash
kind create cluster --config kind-config.yaml
```

Check the nodes - we need 1 control place + 3 workers, according to the manifest
```bash
kubectl get nodes
```

- Now we can move on with the installation of the zalando operator - the operator is a go binary that is deployed with Helm on top of our k8s cluster. It is deployed inside of a POD and what it does is to observe the kubernetes API and create/ fix CDR's that are defined in the k8s API by the same operator.
- Why the CDR is important - the kubernetes knows about his native resources, it knows what is a deployment, what is a pod, a config map, a service,... BUTTTT, in our case the kubernetes cluster doesnt know what a postgres instance means. So it registers a new CDR in the kuberneter control plan and now K8s knows what it should create.
- First, lets clone the git repo of the zalando operator and deploy the chart using Helm.

```bash
git clone --depth 1 --branch v2.0.1 https://github.com/zalando/postgres-operator.git
cd postgres-operator

helm install postgres-operator ./charts/postgres-operator \
  -n postgres-operator --create-namespace
```

- We use the tag version 2.0.1 for stability.
- Already create a dedicated namespace for the postgres operator that we are interested on.

- Check if the pods of the operator are up and if the CDR is registered.
```bash
kubectl -n postgres-operator get pods
kubectl get crd | grep acid.zalan.do      # postgresqls, operatorconfigurations, postgresteams
```

## Exploring the operator

- First lets take a look on the deployment of the operator
```bash
kubectl -n postgres-operator get operatorconfiguration -o yaml 
```

- Manifest of the operator:
```bash
apiVersion: v1
items:
- apiVersion: acid.zalan.do/v1
  configuration:
    aws_or_gcp:
      aws_region: eu-central-1
    connection_pooler:
      connection_pooler_default_cpu_limit: "1"
      connection_pooler_default_cpu_request: 500m
      connection_pooler_default_memory_limit: 100Mi
      connection_pooler_default_memory_request: 100Mi
      connection_pooler_image: ghcr.io/zalando/postgres-operator/pgbouncer:v2.0.1
      connection_pooler_max_db_connections: 60
      connection_pooler_mode: transaction
      connection_pooler_number_of_instances: 2
      connection_pooler_schema: pooler
      connection_pooler_user: pooler
    crd_categories:
    - all
    debug:
      debug_logging: true
      enable_database_access: true
    docker_image: ghcr.io/zalando/spilo-18:4.1-p2
    enable_crd_registration: true
    enable_lazy_spilo_upgrade: false
    enable_maintenance_windows: true
    enable_pgversion_env_var: true
    enable_shm_volume: true
    enable_team_id_clustername_prefix: false
    etcd_host: ""
    kubernetes:
      cluster_domain: cluster.local
      cluster_labels:
        application: spilo
      cluster_name_label: cluster-name
      enable_cross_namespace_secret: false
      enable_finalizers: false
      enable_init_containers: true
      enable_owner_references: false
      enable_persistent_volume_claim_deletion: true
      enable_pod_antiaffinity: false
      enable_pod_disruption_budget: true
      enable_readiness_probe: false
      enable_secrets_deletion: true
      enable_sidecars: true
      master_pod_move_timeout: 20m
      oauth_token_secret_name: postgres-operator
      pdb_master_label_selector: true
      pdb_name_format: postgres-{cluster}-pdb
      persistent_volume_claim_retention_policy:
        when_deleted: retain
        when_scaled: retain
      pod_antiaffinity_preferred_during_scheduling: false
      pod_antiaffinity_topology_key: kubernetes.io/hostname
      pod_management_policy: ordered_ready
      pod_role_label: spilo-role
      pod_service_account_name: postgres-pod
      pod_terminate_grace_period: 5m
      secret_name_template: '{username}.{cluster}.credentials.{tprkind}.{tprgroup}'
      share_pgsocket_with_sidecars: false
      spilo_allow_privilege_escalation: true
      spilo_privileged: false
      storage_resize_mode: pvc
      watched_namespace: '*'
    kubernetes_use_configmaps: true
    load_balancer:
      db_hosted_zone: db.example.com
      enable_master_load_balancer: false
      enable_master_pooler_load_balancer: false
      enable_replica_load_balancer: false
      enable_replica_pooler_load_balancer: false
      external_traffic_policy: Cluster
      master_dns_name_format: '{cluster}.{namespace}.{hostedzone}'
      master_legacy_dns_name_format: '{cluster}.{team}.{hostedzone}'
      replica_dns_name_format: '{cluster}-repl.{namespace}.{hostedzone}'
      replica_legacy_dns_name_format: '{cluster}-repl.{team}.{hostedzone}'
    logging_rest_api:
      api_port: 8080
      cluster_history_entries: 1000
      ring_log_lines: 100
    logical_backup:
      logical_backup_cronjob_environment_secret: ""
      logical_backup_docker_image: ghcr.io/zalando/postgres-operator/logical-backup:v2.0.1
      logical_backup_failed_jobs_history_limit: 3
      logical_backup_job_prefix: logical-backup-
      logical_backup_provider: s3
      logical_backup_s3_access_key_id: ""
      logical_backup_s3_bucket: my-bucket-url
      logical_backup_s3_bucket_prefix: spilo
      logical_backup_s3_endpoint: ""
      logical_backup_s3_region: ""
      logical_backup_s3_retention_time: ""
      logical_backup_s3_secret_access_key: ""
      logical_backup_s3_sse: AES256
      logical_backup_schedule: 30 00 * * *
      logical_backup_successful_jobs_history_limit: 3
      logical_backup_ttl_seconds_after_finished: 86400
    major_version_upgrade:
      major_version_upgrade_mode: manual
      minimal_major_version: "14"
      target_major_version: "18"
    max_instances: -1
    min_instances: -1
    patroni:
      enable_patroni_failsafe_mode: false
    postgres_pod_resources:
      default_cpu_limit: "1"
      default_cpu_request: 100m
      default_memory_limit: 500Mi
      default_memory_request: 100Mi
      min_cpu_limit: 250m
      min_memory_limit: 250Mi
    repair_period: 5m
    resync_period: 30m
    teams_api:
      enable_admin_role_for_users: true
      enable_postgres_team_crd: false
      enable_postgres_team_crd_superusers: false
      enable_team_member_deprecation: false
      enable_team_superuser: false
      enable_teams_api: false
      pam_configuration: https://info.example.com/oauth2/tokeninfo?access_token= uid
        realm=/employees
      pam_role_name: zalandos
      postgres_superuser_teams:
      - postgres_superusers
      protected_role_names:
      - admin
      - cron_admin
      role_deletion_suffix: _deleted
      team_admin_role: admin
      team_api_role_configuration:
        log_statement: all
      teams_api_url: https://teams.example.com/api/
    timeouts:
      patroni_api_check_interval: 1s
      patroni_api_check_timeout: 5s
      pod_deletion_wait_timeout: 10m
      pod_label_wait_timeout: 10m
      ready_wait_interval: 3s
      ready_wait_timeout: 30s
      resource_check_interval: 3s
      resource_check_timeout: 10m
    users:
      enable_password_rotation: false
      password_rotation_interval: 90
      password_rotation_user_retention: 180
      replication_username: standby
      super_username: postgres
    workers: 8
  kind: OperatorConfiguration
  metadata:
    annotations:
      meta.helm.sh/release-name: postgres-operator
      meta.helm.sh/release-namespace: postgres-operator
    creationTimestamp: "2026-11-02T17:46:22Z"
    generation: 1
    labels:
      app.kubernetes.io/instance: postgres-operator
      app.kubernetes.io/managed-by: Helm
      app.kubernetes.io/name: postgres-operator
      helm.sh/chart: postgres-operator-2.0.1
    name: postgres-operator
    namespace: postgres-operator
    resourceVersion: "1327"
    uid: 5e7a1e6c-3503-414f-994e-fef8a9778a6e
kind: List
metadata:
  resourceVersion: ""
```

- Interesting to note that the operator has some default values to it, but in a DBaaS it is interesting to overwrite the operator default values per different clients. Each client has different needs for a database, so we can customize each deployment.
- The docker image is also the spilo by default, and probably we would have some custumized image with our own security checks to be deployed per customer. Important also to mention that maybe the customer himself has his own image with some particularity that he develop on his own and wants to have access to it using a cloud provider infrastructure.
- As we can see pgbouncer is already in the deployment by default - One important details is that maxDBConnections (server-side connections from PgBouncer to Postgres, divided among the pooler pods) should stay bellow max_connections (hard limit of the postgres server).
- Pgbouncer can work in 3 different modes:
    - session mode: connection remains tied to that client for the entire duration of the session until the client disconnects.
    - transaction mode: connection is assigned to a client only for the duration of a single transaction. As soon as the transaction finishes (via COMMIT or ROLLBACK), the server connection is returned to the pool and can be reassigned to a different client.
    - statement mode: A server connection is assigned to a client only for a single SQL statement. (RARELY USED)

- Operator logs:

```bash
kubectl -n postgres-operator logs deploy/postgres-operator -f
```

- It is a good idea to take a look at the operator logs so we can see in real time how it is scheduling new instances.



### Interesting study case regarding postgres performance in k8s:
- Example scenario: during a pgbench run with 150 clients, you see cl_waiting climbing and sv_active stuck at its maximum. Is the bottleneck PgBouncer or Postgres, and what are your two options?
  - In this case the bottleneck is Postgres and we need to analyze the number of max_connections in the deployment - naive approach. Other important point is to check if the postgres has still CPU to be consumed, if the answer is 'yes' we can then increase max_connections and the maxDBConnections with even more pg bouncer instances. In the case the postgres has no headroom, we can than change the deployment of the instance with a vertical scaling on the pod.
  - Important to notice that in case of horizontal scale or having replicas of postgres instances we need to check other things because this would cause writing problems to the database. But because we have more replicas this wouldnt be a problem for having more reads operations.

### Interesting study case regarding postgres high availability in k8s:
- This is a good point to notice why the Zalando operator kept Patroni - a tool to ensure high availability and automatic failover for postgres.
- Not getting into the deeps of Patroni, but the Zalando operator looks like it has the patroni failsafe mode default as 'false'. In the case the K8S api is down by some reason, Patroni would restart the postgres as a read-only replica.
It is like that by having Patroni, in case the K8S API is not reacheable it has its own internal concensus to decide who is the new primary replica - but all instances should answer the concensus, otherwise it will work by demoting the primary instance to a read-only and all writing operations will fail - but the reading ones will remain possible. It is a protective mechanism against disaster.

