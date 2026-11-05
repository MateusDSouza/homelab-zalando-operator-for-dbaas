## Golang Tool

- As we can see golang is used for developing cloud native tools - the zalando postgres operator is written in go and also our backup recovery engine WAL-G is written in go ( previous tool, WAL-E was written in python).
-  Golang is consider a simple language with interfaces, simple and strong concurrency system - goroutines, and simple syntax.
-  With the usage of AI, I could go through the Zalando Operator repo and catch the following:
  
   * pkg/controller/ — the controller: informers watching postgresql resources and queuing events per cluster.
   * pkg/cluster/cluster.go — Create, Update, Delete for one Postgres cluster.
   * pkg/cluster/sync.go — Sync: compares desired vs actual (StatefulSet, services, secrets, volumes) and fixes drift. This is the reconcile loop.
   * pkg/cluster/k8sres.go — how your manifest becomes a StatefulSet spec and the Spilo env vars.
   * pkg/cluster/pod.go / pkg/cluster/majorversionupgrade.go — rolling restarts with switchover, and major upgrade flows.

### Lab + goland tool

- In /failover-probe you can see a small go project that is testing the writing of the data to our lab database deployed and maintained by the operator. The goal of this simple script is to show the understanding of principles of the golang language and how to build a simplistic application that is interacting with our homelab.

- To see the application in action, first we need to forward the port of the pooler to localhost:

```bash
kubectl port-forward svc/acid-demo-pooler 6432:5432
```

- Create the database url as an environment variable and call the script:

```bash
APPPASS=$(kubectl get secret app-owner.acid-demo.credentials.postgresql.acid.zalan.do \
  -o jsonpath='{.data.password}' | base64 -d)
export DATABASE_URL="postgres://app_owner:${APPPASS}@localhost:6432/appdb?sslmode=require"
go run .
```

- Here we can see the execution of the script and the return of the row id that was written in the db and the connection being closed after the execution: ![alt text](../images/go_script_writing_to_db.png)