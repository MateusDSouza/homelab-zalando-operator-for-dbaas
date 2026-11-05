## Providing thousands of database instances in production

- Thinking about the situation of a cloud provider with a DBaaS built on the Zalando PostgreSQL operator and kubernetes clusters: there is the need of automation in certain parts and teams usually work with on-duty calls.
- So, with this in mind some questions came out:
  - How this can be maintained in production? How many operators and k8s clusters we need? Should we have only 1 operator per cluster? 1 operator per namespace? Each customer should have their own namespace on a cluster? What about changing manifests? We cannot do it with a simple kubectl, we need to version this infrastructure and allow rollouts and with sort of gitops (maybe ARGOCD).


- By my research I understood that if we have only 1 cluster in the case of a problem in the control-plane, all primary instances will be demoted. Also, we know that the lock in each replica shoulde be renewed with some sort of frequency - imagine the amount of write operations in the same kubernetes API - this would carry a big overhead for the control plane - will become a huge backend handling requests besides a k8s api.

During the research I found this operator that looks very interesting: **https://github.com/multigres/multigres-operator**

- The golden rule is the following each deployment should be managed by only 1 operator. Other ideas are that, if a client pay for a dedicated cluster, we have so a cluster only for him with one operator that would handle all his deployments where each one of his products would have his own namespace. If the client pay for a shared cluster, we have different small workloads sharing the same cluster and divided by the different name spaces. It still pays off to have different operator handling different workloads per client - even thought they will be sharing the same infrastructure, networking, nodes and so on, but still they would have their workload allocated. It is important to notice that only dividing by namespace is a shallow security - one good practice would be have a dedicated nodepool per client in a shared cluster - each node with its own operator.

- The name space separation is also good because enforce good practices on managing a big portifolio of clients - we have RBAC scoped for the tenant, networking policy, resource quota caps and a simple way of deleting resources based on customer.

### Example of a cloud provider with a Terraform Postgres Provider

Here it is the official terraform provider a DBaaS solution: https://registry.terraform.io/providers/stackitcloud/stackit/latest/docs/resources/postgresflex_database

- The customers can deploy the postgres database using the provider's terraform - from what the provider exposes, it looks like even users who deploy their own infra in the cloud wont be given super user in the database - as a security best practices applied to different clouds.
- But we can then pay attention of the provider and understand what is configurable for the user and do a cross reference with what we have in k8s and the operator work.
  
resource "stackit_postgresflex_database" "example" {
  project_id  = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  instance_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  name        = "mydb"
  owner       = "myusername"
  region      = "dummy-region"
}

- As we can see there is nothing to deploy an ACL for this database, neither the size (what I imagine that by the name of this product we have a scalable postgres, but the user are not defining its cap - also because this would mean that during the usage of the product the user wouldnt be able to write data anymore because of some cap that he defined during the deploy).


### Product Overview
Here we have the offical site of the managed PostgreSQL product: https://docs.stackit.cloud/products/databases/postgresql-flex/

- In the official documentation we can see that what wasnt in the terraform provider can be then achieved using the provider's CLI.
- "Handle thousands of concurrent connections efficiently with Multi-Version Concurrency Control (MVCC). Readers never block writers, ensuring consistent performance under heavy load." - this could be confirmed by the study done of the operator.
- "Protect your data with point-in-time recovery, continuous archiving, and hot standby replicas. Built-in backup tools and write-ahead logging ensure you can recover from any scenario." - also verified during the lab.
-  Here we can see the exactly architecture of the product: https://docs.stackit.cloud/products/databases/postgresql-flex/basics/architecture-of-postgresql-flex/ - I need to do a research on this Thanos, which is new for me.
-  Development is a single instance and prod is 3 replicas - as done in the example using kind.
-  The performance class cannot be change afterwords because of the limitations of k8s pvc storage class is immutable. 
   -  If we need to migrate to a new replica with a different performance class - we have a manual overhead but can be done.