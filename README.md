#GKE k8s bootstrapper

## Overwall architechture

![GKE Cloud Infra Architechture](resources/tmp/gke-bootstrapper-infra.jpg)

![GKE Resources Architechture](resources/tmp/gke-architec.jpg)

## How to use this repository
This section explain how to use this repository to bootstrap a production ready GKE cluster. Change values and script according to your needs, but keep in mind that the defaults are working properly and changes to scripts and YAML's might destroy the sinergy of the scripts.

### Clone the GCP bootstrapper repository

It is required t use Google Cloud Shell. 
Cloud Shell is a stable GCP terminal with access to Cloud resources.  It provides development tools, programming languages compilers and interpreters, and 5Gi of disk available for life. Security can be handled by applying roles glanularity to your GCP User in a organization context. In GCP you should addopt Cloud Shell as your defacto tool. No questions asked. 


```
REPO_URL="https://bitbucket.org/sciensa/gke-bootstrapper/"
git clone $REPO_URL
cd gke-bootstrapper
```
### Fill variables under resources/values.sh

| Parameter                | Description                                                                                                            | Example                                                                                                     |
|--------------------------|------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------|
| `PROJECT_ID`             | gcloud project id                                                                                                      | sandbox-251021                                                                                              |
| `CLUSTER_NAME`           | name of GKE cluster                                                                                                    | sciensa-kub-cluster-001                                                                                     |
| `REGION`                 | VPC region to host infra, OPTIONS = {"lowest_price":["us-central1", "us-west1", "us-east1"], "lowest_latency":["southamerica-east1"]}                                                                                              | us-central1  |
| `OWNER_EMAIL`            | owner email of the GCP account                                                                                         | everton.arakaki@soaexpert.com.br                                                                            |
| `SLACK_URL_WEBHOOK`      | https://lmgtfy.com/?q=how+to+get+slack+webhook+url                                                                     |                                                                                                             |
| `SLACK_CHANNEL`          | Slack channel                                                                                                          | sciensaflix                                                                                      |
| `SLACK_USER`             | Slack user                                                                                                             | flagger                                                                                                     |

### Run GKE provisioner script

To provision the cluster and other necessary resources, use the bellow script.
```
cd resources
./00-build-kubernetes-gcp.sh
```
This will create the underlaying cloud infrastructure for the GKE cluster, deploy a GKE prodcution ready cluster and install three major components:
- helm (package manager)
- istio (service mesh)
- cert-manager (Let's Encrypt TLS certificate manager)

By production ready, it means: Google Kubernetes Engine Multizonal Cluster (4 x n1-standard-2) With Horizontal Node Autoscaling. 

It also deploys a zone under CloudDNS. CloudDNS is the Route53 of GCP. 

The zone is named `istio` and it is configured to work with the GKE istio load balancer.

*Only continue to the next step when the istio objects are up and running. There is a strict dependency of the other objects to istio control plane*

You chan check the progress by running `kubectl get pods -n istio-system`. The ouput should be the following:

```
NAME                                       READY   STATUS      RESTARTS   AGE
istio-citadel-5949896b4b-dfrlh             1/1     Running     0          18m
istio-cleanup-secrets-1.1.12-v67hn         0/1     Completed   0          18m
istio-galley-d87867b67-vh8pd               1/1     Running     0          18m
istio-ingressgateway-7c96766d85-ds6kt      1/1     Running     0          18m
istio-init-crd-10-2-c6wrt                  0/1     Completed   0          18m
istio-init-crd-11-2-52mpn                  0/1     Completed   0          18m
istio-pilot-797844976c-xc2ts               2/2     Running     0          18m
istio-policy-99fd7f7f5-6rdmz               2/2     Running     8          18m
istio-security-post-install-1.1.12-947tm   0/1     Completed   5          18m
istio-sidecar-injector-5b5454d777-nrcj9    1/1     Running     7          18m
istio-telemetry-cdf9c6d7-q9zgj             2/2     Running     8          18m
promsd-76f8d4cff8-nfghj                    2/2     Running     1          18m
```

TODO: Terraform the sh*t out of this script.

#### POSTBUILD: Create Ingress Gateway Letsencrypt certificate and configure DNS

##### Confige DNS
Under CloudDNS, go to the created zone and copy the nameservers created for your domain:

    ns-cloud-c1.googledomains.com.
    ns-cloud-c2.googledomains.com.
    ns-cloud-c3.googledomains.com.
    ns-cloud-c4.googledomains.com.

Edit your domain provider to use the nameservers gathered previusly.

##### Gateway certificate
Edit file `resourses/tmp/ssl-certificates/10-istio-gateway-cert.yaml`, changing `commonName` and `domains` entries with your domain information:
```
apiVersion: certmanager.k8s.io/v1alpha1
kind: Certificate
metadata:
  name: istio-gateway
  namespace: istio-system
spec:
  secretName: istio-ingressgateway-certs
  issuerRef:
    name: letsencrypt-prod
  commonName: "*.YOURDOMAIN.COM"
  acme:
    config:
    - dns01:
        provider: cloud-dns
      domains:
      - "*.YOURDOMAIN.COM"
      - "YOURDOMAIN.COM"
```
This is a wildcarded certificate, meaning that all subdomains connections will be wrapped with TLS using one and only one certificate.
use `kubectl -n istio-system get certificates` to check certificate progress, when the certificate is Ready, use `kubectl -n istio-system delete pods -l istio=ingressgateway` to kill the ingress pod and renew secrets.

To debug possible errors, use:
```
kubectl -n cert-manager get pods
kubectl -n cert-manager logs -f <cert-manager-xxxxxx-xxxxxxx>
```

For testing, you can copy and paste the bellow code (of course, change DOMAIN to your domain): 

```
DOMAIN="evertonarakaki.tk"
helm repo add sp https://stefanprodan.github.io/podinfo
helm upgrade my-release --install sp/podinfo 
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: test-gke-pod
  namespace: default
spec:
  hosts:
   - "test-gke-pod.${DOMAIN}"
  gateways:
  - public-gateway.istio-system.svc.cluster.local
  http:
  - route:
    - destination:
        host: my-release-podinfo
        port:
          number: 9898
EOF
```

To cleanup this test pod, run:

```
helm delete --purge my-release
kubectl delete virtualservice test-gke-pod
```

Access https://test-gke-pod.${DOMAIN}. If you have an error, you probably forgot to delete the istio-gateway pod or to change tour nameserver config.

From now on, your cluster is ready to be used. It is a raw cluster, no observability by default. We recommend following the bellow steps to deploy the mon, log and cid stack.

### Run LOG provisioner script

To provision logging resources, use the bellow script.
```
./10-build-log-objects.sh
```

This will provision 3 log resources:
- Elasticsearch (3 nodes) as Statefulset
- Fluentd as Daemonset (spread all over the VM's)
- Kibana 

You chan check the progress by running `kubectl -n log get pods`. The ouput should be the following:

```
NAME                              READY   STATUS    RESTARTS   AGE
elasticsearch-0                   2/2     Running   0          2m12s
elasticsearch-1                   2/2     Running   0          83s
elasticsearch-2                   2/2     Running   0          52s
fluentd-6825s                     2/2     Running   1          2m10s
fluentd-fl579                     2/2     Running   1          2m10s
fluentd-lnjqt                     2/2     Running   1          2m10s
fluentd-vl5xq                     2/2     Running   1          2m10s
kibana-logging-5db895d95c-hr8ds   2/2     Running   0          2m9s
```

As Kibana does not provide a authentication, I chose not to keep it public. To access Kibana (https://kibana-log.YOURDOMAIN.COM), run the bellow command (can be found under resourses/tmp/istio-virtual-services/log/kibana-log-vs.yaml)

```
DOMAIN="evertonarakaki.tk"
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: kibana
  namespace: log
spec:
  hosts:
  - "kibana-log.${DOMAIN}"
  gateways:
  - public-gateway.istio-system.svc.cluster.local
  http:
  - route:
    - destination:
        host: kibana-logging
EOF
```

Kibana is not configured and it will require further work to have enhanced observability, but the fluentd daemonset is already collecting data from all applications logging to stdout. To check it, create an index pattern `*` and bound to `@timestamp`. This will give you some nice information on *Discover* window:

```
September 6th 2019, 15:49:04.000	GET /api/status 200 2ms - 9.0B
September 6th 2019, 15:49:02.000	GET /api/status 200 6ms - 9.0B
September 6th 2019, 15:48:54.000	GET /api/status 200 2ms - 9.0B
```

Delete the VirtualService when you are done playing around. It is not safe to have Kibana open to the world.

```
kubectl -n log  delete virtualservice kibana 
```

TODO: implement security authentication layer over Kibana

### Run MON provisioner script

To provision logging resources, use the bellow script.
```
./10-build-mon-objects.sh
```

You chan check the progress by running `kubectl -n log get pods`. The ouput should be the following:

```
alertmanager-d5475f677-4d4xl            2/2     Running   0          22m
grafana-6ddd9cc4d5-7ptst                3/3     Running   0          81s
kube-state-metrics-d575c5f88-x25gg      3/3     Running   2          22m
node-exporter-7spfm                     1/1     Running   0          22m
node-exporter-rsjbn                     1/1     Running   0          22m
node-exporter-szgdp                     1/1     Running   0          22m
node-exporter-vpbbv                     1/1     Running   0          22m
prometheus-deployment-5466b4584-glxv2   2/2     Running   0          22m
```

There are 4 Dashboards already configured + alertmanager sending slackwebhooks in case some metrics goes wild. 

To visualize the grafana, use be bellow code, replacing the DOMAIN value with your domain. 

```
DOMAIN="evertonarakaki.tk"
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: grafana
  namespace: mon
spec:
  hosts:
  - "grafana-mon.${DOMAIN}"
  gateways:
  - public-gateway.istio-system.svc.cluster.local
  http:
  - route:
    - destination:
        host: grafana
EOF
```

Default admin user is `admin` and the password can be gathered with:
```
kubectl get secret --namespace mon grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

It is a best practice to create readonly users to bussiness guys and first level support. 

## Operators manual

Shutdown cluster:
```
gcloud container clusters resize sciensa-kub-cluster-001 --num-nodes=0 --region=us-central1 --node-pool=default-pool
gcloud container clusters resize sciensa-kub-cluster-001 --num-nodes=0 --region=us-central1 --node-pool=pool-horizontal-autoscaling
```

Turn on cluster:
```
gcloud container clusters resize sciensa-kub-cluster-001 --num-nodes=1 --region=us-central1 --node-pool=default-pool
gcloud container clusters resize sciensa-kub-cluster-001 --num-nodes=1 --region=us-central1 --node-pool=pool-horizontal-autoscaling
```

Interesting alias:
```
alias klog="kubectl -n log"
alias kmon="kubectl -n mon"
alias kcid="kubectl -n cid"
alias kdev="kubectl -n dev"
alias kite="kubectl -n ite"
alias kprd="kubectl -n prd"
```

Force Deployment/Statefulset update without deleting
```
kmon patch deployments prometheus-deployment -p  "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"dummy-date\":\"`date +'%s'`\"}}}}}"
```

# Below is not ok, still TBD

###### Configure Jenkins to deploy to Kubernetes

When creating a new pipeline, use `Setup Kubernetes CLI (kubectl)` plugin to deploy to the kubernetes cluster. You will need to configure a credential. See bellow how to configure the credential.

####### Create a ServiceAccount named `jenkins-dev-robot` in a given namespace.
```
kubectl -n dev create serviceaccount jenkins-dev-robot
kubectl -n ite create serviceaccount jenkins-ite-robot
kubectl -n prd create serviceaccount jenkins-prd-robot
```
####### The next line gives `jenkins-robot` administator permissions for this namespace.
```
kubectl -n dev create rolebinding jenkins-dev-robot-binding --clusterrole=cluster-admin --serviceaccount=jenkins-dev-robot
kubectl -n ite create rolebinding jenkins-ite-robot-binding --clusterrole=cluster-admin --serviceaccount=jenkins-ite-robot
kubectl -n prd create rolebinding jenkins-prd-robot-binding --clusterrole=cluster-admin --serviceaccount=jenkins-prd-robot
```
####### Get the name of the token that was automatically generated for the ServiceAccount `jenkins-robot`.
```
kubectl -n dev get serviceaccount jenkins-dev-robot -o go-template --template='{{range .secrets}}{{.name}}{{"\n"}}{{end}}'
kubectl -n ite get serviceaccount jenkins-ite-robot -o go-template --template='{{range .secrets}}{{.name}}{{"\n"}}{{end}}'
kubectl -n prd get serviceaccount jenkins-prd-robot -o go-template --template='{{range .secrets}}{{.name}}{{"\n"}}{{end}}'
```
####### Retrieve the token and decode it using base64.
```
kubectl -n <NAMESPACE> get secrets <SECRETNAME> -o go-template --template '{{index .data "token"}}' | base64 -D
```

On Jenkins, navigate in the folder you want to add the token in, or go on the main page. Then click on the "Credentials" item in the left menu and find or create the "Domain" you want. Finally, paste your token into a Secret text credential. The ID is the credentialsId you need to use in the plugin configuration.


### Building Block Continous Integration / Continous Delivery

```
```



helm install --name my-release stable/grafana
