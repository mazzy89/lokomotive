---
title: Lokomotive AWS quickstart guide
weight: 10
---

## Introduction

This quickstart guide walks through the steps needed to create a Lokomotive cluster on AWS.

Lokomotive runs on top of [Flatcar Container Linux](https://www.flatcar-linux.org/). This guide
uses the `stable` channel.

The guide uses [Amazon Route 53](https://aws.amazon.com/route53/) as a DNS provider. For more
information on how Lokomotive handles DNS, refer to [this](../concepts/dns.md) document.

Lokomotive can store Terraform state [locally](../configuration-reference/backend/local.md)
or remotely within an [AWS S3 bucket](../configuration-reference/backend/s3.md). By default, Lokomotive
stores Terraform state locally.

[Lokomotive components](../concepts/components.md) complement the "stock" Kubernetes functionality
by adding features such as load balancing, persistent storage and monitoring to a cluster. To keep
this guide short you will deploy a single component - `httpbin` - which serves as a demo
application to verify the cluster behaves as expected.

By the end of this guide, you'll have a production-ready Kubernetes cluster running on AWS.

## Requirements

* Basic understanding of Kubernetes concepts.
* An AWS account and IAM credentials.
* An AWS
  [access key ID and secret](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html)
  of a user with
  [permissions](https://github.com/kinvolk/lokomotive/blob/master/docs/concepts/dns.md#aws-route-53)
  to edit Route 53 records.
* An AWS Route 53 zone (can be a subdomain).
* Terraform v0.13.x installed locally.
* An SSH key pair for management access.
* Terraform `v0.13.x`
  [installed](https://learn.hashicorp.com/terraform/getting-started/install.html#install-terraform).
* `kubectl` [installed](https://kubernetes.io/docs/tasks/tools/install-kubectl/).

>NOTE: The `kubectl` version used to interact with a Kubernetes cluster needs to be compatible with
>the version of the Kubernetes control plane. Ideally you should install a `kubectl` binary whose
>version is identical to the Kubernetes control plane included with a Lokomotive release. However,
>some degree of version "skew" is tolerated - see the Kubernetes
>[version skew policy](https://kubernetes.io/docs/setup/release/version-skew-policy/) document for
>more information. You can determine the version of the Kubernetes control plane included with a
>Lokomotive release by looking at the [release notes][releases].


## Steps

### Step 1: Install lokoctl

`lokoctl` is the command-line interface for managing Lokomotive clusters.

Download the latest `lokoctl` binary for your platform:

```console
export os=linux  # For macOS, use `os=darwin`.

export release=$(curl -s https://api.github.com/repos/kinvolk/lokomotive/releases | jq -r '.[0].name' | tr -d v)
curl -LO "https://github.com/kinvolk/lokomotive/releases/download/v${release}/lokoctl_${release}_${os}_amd64.tar.gz"
```

Extract the binary and copy it to a place under your `$PATH`:

```console
tar zxvf lokoctl_${release}_${os}_amd64.tar.gz
sudo cp lokoctl_${release}_${os}_amd64/lokoctl /usr/local/bin
rm -rf lokoctl_${release}_${os}_amd64*
```

### Step 2: Create a cluster configuration

Create a directory for the cluster-related files and navigate to it:

```console
mkdir lokomotive-demo && cd lokomotive-demo
```

Create a file named `cluster.lokocfg` with the following contents:

```hcl
cluster "aws" {
  asset_dir            = "./assets"
  cluster_name         = "lokomotive-demo"
  controller_count     = 1
  dns_zone             = "example.com"
  dns_zone_id          = "ZQC39L1XVW0D"
  ignore_x509_cn_check = true

  project_id           = "89273817-4f44-4b41-9f0c-cb00bf538542"
  region               = "us-east-1"

  ssh_pubkeys          = ["ssh-rsa AAAA..."]

  worker_pool "pool-1" {
    count         = 2
    instance_type = "i3.large"
    ssh_pubkeys   = ["ssh-rsa AAAA..."]
  }
}

# A demo application.
component "httpbin" {
  ingress_host = "httpbin.example.com"
}
```

Replace the parameters above using the following information:

- `dns_zone` - a Route 53 zone name. A subdomain will be created under this zone in the following
  format: `<cluster_name>.<zone>`
- `dns_zone_id` - a Route 53 DNS zone ID which can be found in your AWS console.
- `project_id` - the Packet project ID to deploy the cluster in.
- `ssh_pubkeys` - A list of strings representing the *contents* of the public SSH keys which should
  be authorized on cluster nodes.

The rest of the parameters may be left as-is. For more information about the configuration options
see the [configuration reference](../configuration-reference/platforms/aws.md).


### Step 3: Deploy the cluster

>NOTE: If you have the AWS CLI installed and configured for an AWS account, you can skip setting
>the `AWS_*` variables below. `lokoctl` follows the standard AWS authentication methods, which
>means it will use the `default` AWS CLI profile if no explicit credentials are specified.
>Similarly, environment variables such as `AWS_PROFILE` can be used to instruct `lokoctl` to use a
>specific AWS CLI profile for AWS authentication.

Set up your Packet and AWS credentials in your shell:

```console
export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7FAKE
export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYFAKE
```

Add a private key corresponding to one of the public keys specified in `ssh_pubkeys` to your `ssh-agent`:

```bash
ssh-add ~/.ssh/id_rsa
ssh-add -L
```

Deploy the cluster:

```console
lokoctl cluster apply -v
```

The deployment process typically takes about 15 minutes. Upon successful completion, an output
similar to the following is shown:

```
Your configurations are stored in ./assets

Now checking health and readiness of the cluster nodes ...

Node                             Ready    Reason          Message                            
                                                                                             
lokomotive-demo-controller-0       True     KubeletReady    kubelet is posting ready status    
lokomotive-demo-pool-1-worker-0    True     KubeletReady    kubelet is posting ready status    
lokomotive-demo-pool-1-worker-1    True     KubeletReady    kubelet is posting ready status    

Success - cluster is healthy and nodes are ready!
```
## Verification

Use the generated `kubeconfig` file to access the cluster:

```console
export KUBECONFIG=$(pwd)/assets/cluster-assets/auth/kubeconfig
kubectl get nodes
```

Sample output:

```
NAME                            STATUS   ROLES    AGE   VERSION
lokomotive-demo-controller-0      Ready    <none>   33m   v1.17.4
lokomotive-demo-pool-1-worker-0   Ready    <none>   33m   v1.17.4
lokomotive-demo-pool-1-worker-1   Ready    <none>   33m   v1.17.4
```

Verify all pods are ready:

```console
kubectl get pods -A
```

Verify you can access httpbin:

```console
kubectl -n httpbin port-forward svc/httpbin 8080

# In a new terminal.
curl http://localhost:8080/get
```

Sample output:

```
{
  "args": {}, 
  "headers": {
    "Accept": "*/*", 
    "Host": "localhost:8080", 
    "User-Agent": "curl/7.70.0"
  }, 
  "origin": "127.0.0.1", 
  "url": "http://localhost:8080/get"
}
```

## Using the cluster

At this point you should have access to a Lokomotive cluster and can use it to deploy applications.

If you don't have any Kubernetes experience, you can check out the [Kubernetes
Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/deploy-app/deploy-intro/) tutorial.

>NOTE: Lokomotive uses a relatively restrictive Pod Security Policy by default. This policy
>disallows running containers as root. Refer to the
>[Pod Security Policy documentation](../concepts/securing-lokomotive-cluster.md#cluster-wide-pod-security-policy)
>for more details.

## Cleanup

To destroy the Lokomotive cluster, execute the following command:

```console
lokoctl cluster destroy --confirm
```

You can safely delete the working directory created for this quickstart guide if you no longer
require it.

## Troubleshooting

### Stuck At Copy Controller Secrets

If there is an execution error or no progress beyond the output provided below:

```console
...
module.aws-myawscluster.null_resource.copy-controller-secrets: Still creating... (8m30s elapsed)
module.aws-myawscluster.null_resource.copy-controller-secrets: Still creating... (8m40s elapsed)
...
```

The error probably happens because the `ssh_pubkeys` provided in the configuration is missing in the
`ssh-agent`.

In case the deployment process seems to hang at the `copy-controller-secrets` phase for a long
time, check the following:

- Verify the correct private SSH key was added to `ssh-agent`.
- Verify that you can SSH into the created controller node from the machine running `lokoctl`.

### IAM Permission Issues

  * If the failure is due to insufficient permissions, check the IAM policy and follow the [IAM troubleshooting guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/troubleshoot.html).

## Conclusion

After walking through this guide, you've learned how to set up a Lokomotive cluster on AWS.

## Next steps

You can now start deploying your workloads on the cluster.

For more information on installing supported Lokomotive components, you can visit the [component
configuration references](../configuration-reference/components).

[releases]: https://github.com/kinvolk/lokomotive/releases
