## Deploying PostgreSQL instances and exploring the operator

- In the manifests we have our acid-demo.yaml that is deploying 3 postgreSQL instances. The postgreSQL version used is the 17, as required by the operator the teamID is called acid and we have and the following values for the pods:

- volume:
  size: 1Gi                                  # 1 GiB disk (PVC) per Postgres pod
- resources:
  requests: {cpu: 100m, memory: 256Mi}       # guaranteed minimum, used for scheduling
  limits:   {cpu: 500m, memory: 512Mi}       # hard ceiling at runtime

- Also the operator create the users of the databases based on the manifest and automatically generate random passwords that are stored in the kubernetes secrets.
- We should give a superuser to a costumer - abstract the adm of the postgreSQL.
- We get the superuser by default because of the operator - we are managing the different instances.
  
## Exploration

mateus.desouza@SDGESP-6YGQ97WG ~ % kubectl get pods -l cluster-name=acid-demo -L spilo-role -o wide

NAME          READY   STATUS    RESTARTS   AGE     IP           NODE             NOMINATED NODE   READINESS GATES   SPILO-ROLE
acid-demo-0   1/1     Running   0          3m56s   10.244.2.3   pg-lab-worker    <none>           <none>            master
acid-demo-1   1/1     Running   0          3m2s    10.244.3.3   pg-lab-worker2   <none>           <none>            replica
acid-demo-2   1/1     Running   0          2m14s   10.244.1.4   pg-lab-worker3   <none>           <none>            replica
mateus.desouza@SDGESP-6YGQ97WG ~ %


- We can see here who is the master by the SPILO-ROLE.
  
mateus.desouza@SDGESP-6YGQ97WG ~ % kubectl get sts,svc,secret,pdb,cm -l cluster-name=acid-demo
NAME                         READY   AGE
statefulset.apps/acid-demo   3/3     5m4s

NAME                     TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
service/acid-demo        ClusterIP   10.96.221.4    <none>        5432/TCP   5m4s
service/acid-demo-repl   ClusterIP   10.96.32.230   <none>        5432/TCP   5m4s

NAME                                                              TYPE     DATA   AGE
secret/app-owner.acid-demo.credentials.postgresql.acid.zalan.do   Opaque   2      5m4s
secret/app-user.acid-demo.credentials.postgresql.acid.zalan.do    Opaque   2      5m4s
secret/postgres.acid-demo.credentials.postgresql.acid.zalan.do    Opaque   2      5m4s
secret/standby.acid-demo.credentials.postgresql.acid.zalan.do     Opaque   2      5m4s

NAME                                                            MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/postgres-acid-demo-critical-op-pdb   N/A             0                 0                     5m4s
poddisruptionbudget.policy/postgres-acid-demo-pdb               1               N/A               0                     5m4s

NAME                         DATA   AGE
configmap/acid-demo-config   0      4m6s
configmap/acid-demo-leader   0      4m3s
mateus.desouza@SDGESP-6YGQ97WG ~ %ç

- We can see all the secrets created inside the kubernetes secrets for each users we define in our manifest acid-demo.yaml. The operator handles the creation of all those resources, their internal networking (inside the cluster).

SDGESP-6YGQ97WG:zalando-postgres-operator-lab mateus.desouza$ kubectl exec -it acid-demo-0 -- patronictl list
+ Cluster: acid-demo (7703934128535535679) ------+----+-------------+-----+------------+-----+
| Member      | Host       | Role    | State     | TL | Receive LSN | Lag | Replay LSN | Lag |
+-------------+------------+---------+-----------+----+-------------+-----+------------+-----+
| acid-demo-0 | 10.244.2.3 | Leader  | running   |  1 |             |     |            |     |
| acid-demo-1 | 10.244.3.3 | Replica | streaming |  1 |   0/51FFD78 |   0 |  0/51FFD78 |   0 |
| acid-demo-2 | 10.244.1.4 | Replica | streaming |  1 |   0/51FFD78 |   0 |  0/51FFD78 |   0 |
+-------------+------------+---------+-----------+----+-------------+-----+------------+-----+
SDGESP-6YGQ97WG:zalando-postgres-operator-lab mateus.desouza$ 


- Here we can see the Patroni pointing to the same acid-demo-0 as the master and the others as replicas - ensuring the high availability as a native tool for distributed systems.

### Import things to understand with this setup of Zalando
- There are 2 different services here in the postgreSQL: 1 instance is the master and all the others are replicas (check the spilo-role). Spilo gives us one image that has postgres + patroni + wal-g. Patroni is runnig inside every pod - 3 in this homelab, and patroni is the one responsible to handle the HA in this distributed system. But the operator itself is the one that creates and reconciles the kubernetes objects - deployments, intances, number of intances, secrets, configmaps and so on...
- In the case of changing from one instance to another as the master, what happens is that  patroni sets the new master and the services just start selecting the new master choosen by patroni - this let the responsability well divided in the cluster.

- There are other architectures that manage this high availability differently.