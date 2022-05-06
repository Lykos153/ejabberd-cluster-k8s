# ejabberd-cluster-k8s
A Kustomization for an [ejabberd](https://www.ejabberd.im) cluster in Kubernetes using leader election.

## Usage



## Alternative solutions
https://github.com/processone/docker-ejabberd/issues/64 contains multiple approaches:
1. [karimhm's solution](https://github.com/processone/docker-ejabberd/issues/64#issuecomment-814310376) which was the inspiration for this one. It calls the K8s API to get a list of Pods which it then tries to join. Turned out to be fragile when scaling up from 0 Pods (eg. during initial deployment or after all Pods crashed) and lead to split-brain situations.
2. https://github.com/Robbilie/kubernetes-ejabberd doesn't need a custom image or API access and solely relies on DNS requests and headless services. Doesn't keep Pods in unready state until they joined the cluster. Also doesn't make sure that all Pods join the same cluster.
3. An [approach for docker-compose](https://github.com/processone/docker-ejabberd/issues/64#issuecomment-887741332) that could be adapted to K8s. Doesn't scale very, as it would need a separate Service for each replica.
