# Database Cluster, Databases and Tables

## 1. Introduction
A database cluster is the entire set of databases managed by a PostgreSQL instance and a database per se is a collection of tables organized locally under this structure. This hierarchy is essential to nderstand how PostgresSQL manages data internally.

## 1.1 Logical Structure of a Database Cluster

A database cluster is a collection of databases managed by a PostgreSQL instance. A postgres runs on a single server as a single instance, but inside of this DBMS we can have several different database objects, each of those is a logical entity inside of the DBMS.
Inside of each database we have different structures: tables, indexes, sequences, views and functions - each one of those belongs to a single database and they are all organized inside of a database that belongs to a set of databases called database clusters.
Interesting finding: we have the relationship of 1 instance per 1 database cluster.

All database objects in PostgreSQL are internally managed by respective OID's. We can find those in the system catalogs:

```sql
SELECT datname, oid FROM pg_database WHERE datname = 'sampledb';
```

```sql
SELECT relname, oid FROM pg_class WHERE relname = 'sampletbl';
```

During my experimentation I could see that the connection to the db using my kubectl port forward as not sustainable, I was having a lot of connection crashes as you can see here:

```bash
mateus.desouza@SDGESP-6YGQ97WG ~ % kubectl port-forward svc/acid-demo-pooler 5432:5432 -n default
Forwarding from 127.0.0.1:5432 -> 5432
Forwarding from [::1]:5432 -> 5432
Handling connection for 5432
Handling connection for 5432
Handling connection for 5432
Handling connection for 5432
E1110 10:28:03.026492   97111 portforward.go:549] "An error occurred forwarding" err="error forwarding port 5432 to pod 226b6fdf718fcb728be27ae62c811b6229cde29f7eabfddf974a63bfe2ea5b00, uid : failed to execute portforward in network namespace \"/var/run/netns/cni-06a2c7b9-679b-7e97-ff70-ed0ecc1b3013\": writeto tcp4 127.0.0.1:52562->127.0.0.1:5432: read tcp4 127.0.0.1:52562->127.0.0.1:5432: read: connection reset by peer" localPort=5432 remotePort=5432
error: lost connection to pod
mateus.desouza@SDGESP-6YGQ97WG ~ % kubectl port-forward svc/acid-demo-pooler 5432:5432 -n default
Forwarding from 127.0.0.1:5432 -> 5432
Forwarding from [::1]:5432 -> 5432
Handling connection for 5432
Handling connection for 5432
Handling connection for 5432
Handling connection for 5432
Handling connection for 5432
Handling connection for 5432
E1110 10:40:07.640337    5411 portforward.go:549] "An error occurred forwarding" err="error forwarding port 5432 to pod 226b6fdf718fcb728be27ae62c811b6229cde29f7eabfddf974a63bfe2ea5b00, uid : failed to execute portforward in network namespace \"/var/run/netns/cni-06a2c7b9-679b-7e97-ff70-ed0ecc1b3013\": writeto tcp4 127.0.0.1:39608->127.0.0.1:5432: read tcp4 127.0.0.1:39608->127.0.0.1:5432: read: connection reset by peer" localPort=5432 remotePort=5432
error: lost connection to pod
```

I need to find a way to have a better stable connection or I would need to use the pgclient pod that I have in my cluster - the problem is that I would have the facilities from this extension. Another alternative is to create a stable service open to my private network.

I learned that because I am using Kind for practicing with my db, this has an isolation because of docker. The official k8s team develop a good alternative that would help developers experiment with Kind as they would do in a normal cloud environment - cloud-provider-kind.

What is the problem, we have 3 different layers of network in the case of this homelab - the key is, my extension in vscode need a real IP to connect to a database and because we have it deployed in kind - kubernetes assigned an internal IP to the postgres and we can do quickly connection for debugging purposes using the portforward, but this is not consistent and the connection will not persist. We need to act and deploy a loadbalance.

How to setup this load balance:

```bash
brew install cloud-provider-kind
```

As we will route network traffic a default permission maybe will not allow to do so, we need to execute the cloud-provider-kind with the permissions to be able to route. In the corporative notebook you can request for admin priviledges for a limited amount of time, but in a personal computer you can authenticate using sudo.

```bash
sudo cloud-provider-kind
```

Once this is done, we need to start the cloud-provider-kind in a terminal and let it open there - this will be our loadbalancer with the public IP (doubt: is this IP really public? Someone in the network could get my real IP address and reach out for the cluster in this way)

The goal here should be to then patch the service of the homelab to this loadbalancer

```bash
kubectl patch svc acid-demo-pooler -n default -p '{"spec": {"type": "LoadBalancer"}}'
```

Result, tunnel complete:
```bash
                protocol: TCP
I1110 11:58:54.442696   25959 server.go:167] updating loadbalancer tunnels on userspace
I1110 11:58:54.500327   25959 tunnel.go:36] found port maps map[10000/tcp:52660 5432/tcp:52661] associated to container kindccm-54ef1b5f890c
I1110 11:58:54.555980   25959 tunnel.go:43] setting IPv4 address 172.18.0.6 associated to container kindccm-54ef1b5f890c
I1110 11:58:54.634008   25959 tunnel.go:142] Starting tunnel on 172.18.0.6:10000 tcp
I1110 11:58:54.638049   25959 tunnel.go:142] Starting tunnel on 172.18.0.6:5432 tcp
I1110 11:58:54.638184   25959 server.go:175] get loadbalancer status
I1110 11:58:54.707910   25959 controller.go:985] Patching status for service default/acid-demo-pooler
I1110 11:58:54.707945   25959 event.go:395] "Event occurred" object="default/acid-demo-pooler" fieldPath="" kind="Service" apiVersion="v1" type="Normal" reason="EnsuredLoadBalancer" message="Ensured load balancer"
```

Now, to retrieve the IP of the service:

```bash
kubectl get svc acid-demo-pooler -n default
```

```bash
mateus.desouza@SDGESP-6YGQ97WG ~ % kubectl get svc acid-demo-pooler -n default
NAME               TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
acid-demo-pooler   LoadBalancer   10.96.169.46   172.18.0.6    5432:32104/TCP   5d20h
```

Now with the connection stablished I can then query and explore it!


## 1.2 Physical Structure of Database Cluster

