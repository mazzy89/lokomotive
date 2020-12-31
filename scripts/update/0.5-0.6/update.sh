#!/bin/bash

set -euo pipefail

readonly script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
readonly namespace="update-host-files"

kubectl create ns $namespace --dry-run=client -o yaml | kubectl apply -f -
kubectl create -n $namespace cm script --from-file "${script_dir}"/cluster.sh --dry-run=client -o yaml | kubectl apply -f -

for nodename in $(kubectl get nodes -ojsonpath='{.items[*].metadata.name}')
do
  node_labels=$(kubectl get node $nodename --show-labels)
  if echo "${node_labels}" | grep 'metallb.lokomotive.io/my-asn' > /dev/null; then
    kubectl label node --overwrite $nodename lokomotive.alpha.kinvolk.io/bgp-enabled=true
    mode="metallb"
  elif echo "${node_labels}" | grep 'node.kubernetes.io/master' > /dev/null;  then
    mode="controller"
  else
    mode="general"
  fi

  echo "
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: uhf-$nodename
  name: uhf-$nodename
  namespace: $namespace
spec:
  containers:
  - image: registry.fedoraproject.org/fedora:32
    name: update-host-files
    imagePullPolicy: IfNotPresent
    securityContext:
      privileged: true
    args:
    - sh
    - -c
    - bash /tmp/script/cluster.sh $mode
    volumeMounts:
    - name: etc-kubernetes
      mountPath: /etc/kubernetes/
    - name: script
      mountPath: /tmp/script/
    - name: rkt-etcd
      mountPath: /etc/systemd/system/etcd-member.service.d/
  nodeName: $nodename
  restartPolicy: Never
  hostPID: true
  volumes:
  - name: etc-kubernetes
    hostPath:
      path: /etc/kubernetes/
  - name: script
    configMap:
      name: script
  - name: rkt-etcd
    hostPath:
      path: /etc/systemd/system/etcd-member.service.d/
" | kubectl apply -f -

  while true
  do
    # Get an exit code. Does not matter if it zero or otherwise, this endless loop will stop once
    # the pod has exited.
    complete=$(kubectl -n $namespace get pod uhf-$nodename -o jsonpath='{.status.containerStatuses[-1].state.terminated.exitCode}')
    if [ -z "${complete}" ]; then
      echo "waiting for pod uhf-$nodename to finish"
    else
      kubectl -n $namespace logs uhf-$nodename
      break
    fi
    sleep 1
  done
  echo '-------------------------------------------------------------------------------------------'
done
