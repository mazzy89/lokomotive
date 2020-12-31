#!/bin/bash

# This script:
# 1) Appends the label `lokomotive.alpha.kinvolk.io/bgp-enabled=true` in the env file for the nodes
#    running metallb.
# 2) Update the image tag of Kubelet.
# 3) Update etcd if it is a controller node.

set -euo pipefail

mode=$1

function run_on_host() {
  nsenter -a -t 1 /bin/sh -c "${1}"
}

function update_kubelet_env_file() {
  echo -e "\nUpdating Kubelet env file...\nOld Kubelet env file:\n"
  cat /etc/kubernetes/kubelet.env

  label=$(grep ^NODE_LABELS /etc/kubernetes/kubelet.env)
  label_prefix="${label::-1}"
  augmented_label="${label_prefix},lokomotive.alpha.kinvolk.io/bgp-enabled=true\""

  # This copy is needed because `sed` tries to create a new file, this changes the file inode and
  # docker does not allow it. We make changes using `sed` to a temporary file and then overwrite
  # contents of temporary file to the actual file.
  cp /etc/kubernetes/kubelet.env /kubelet.env

  # Update the label on MetalLB nodes.
  if [ "${mode}" = "metallb" ]; then
    sed -i "s|^NODE_LABELS.*|${augmented_label}|g" /kubelet.env
  fi

  # Update the kubelet image version.
  if grep amd64 /kubelet.env > /dev/null; then
    sed -i "s|^KUBELET_IMAGE_TAG.*|KUBELET_IMAGE_TAG=v1.19.4-amd64|g" /kubelet.env
  else
    sed -i "s|^KUBELET_IMAGE_TAG.*|KUBELET_IMAGE_TAG=v1.19.4-arm64|g" /kubelet.env
  fi

  # Replace the contents of original file with temporary file.
  cat /kubelet.env > /etc/kubernetes/kubelet.env

  echo -e "\nNew Kubelet env file:\n"
  cat /etc/kubernetes/kubelet.env
}

function update_kubelet_config_file() {
  if [ "${mode}" != "metallb" ]; then
    return
  fi

  echo -e "\nUpdating Kubelet config creator file...\nOld Kubelet config creator file:\n"
  cat /etc/kubernetes/configure-kubelet-cgroup-driver

  cp /etc/kubernetes/configure-kubelet-cgroup-driver /configure-kubelet-cgroup-driver
  sed -i "s|^EOF|providerID: external|g" /configure-kubelet-cgroup-driver
  echo "EOF" >> /configure-kubelet-cgroup-driver
  cat /configure-kubelet-cgroup-driver > /etc/kubernetes/configure-kubelet-cgroup-driver

  echo -e "\nNew Kubelet config creator file:\n"
  cat /etc/kubernetes/configure-kubelet-cgroup-driver
}

function restart_host_kubelet() {
  echo -e "\nRestarting Kubelet...\n"
  run_on_host "systemctl restart kubelet && systemctl status --no-pager kubelet"
}

function update_etcd() {
  if [ "${mode}" != "controller" ]; then
    return
  fi

  rkt_etcd_cfg="/etc/systemd/system/etcd-member.service.d/40-etcd-cluster.conf"
  docker_etcd_cfg="/etc/kubernetes/etcd.env"
  readonly etcd_version="v3.4.13"

  if [ -f "${rkt_etcd_cfg}" ]; then
    cfg_file="${rkt_etcd_cfg}"
    sed_cmd="sed -i 's|^Environment=\"ETCD_IMAGE_TAG.*|Environment=\"ETCD_IMAGE_TAG=${etcd_version}\"|g' /etcd.env"
    restart_etcd_command="systemctl is-active etcd-member && systemctl restart etcd-member && systemctl status --no-pager etcd-member"

  elif [ -f "${docker_etcd_cfg}" ]; then
    cfg_file="${docker_etcd_cfg}"
    sed_cmd="sed -i 's|^ETCD_IMAGE_TAG.*|ETCD_IMAGE_TAG=${etcd_version}|g' /etcd.env"
    restart_etcd_command="systemctl is-active etcd && systemctl restart etcd && systemctl status --no-pager etcd"
  fi

  echo -e "\nUpdating etcd file...\nOld etcd file:\n"
  cat "${cfg_file}"
  cp "${cfg_file}" /etcd.env

  eval "${sed_cmd}"

  cat /etcd.env > "${cfg_file}"

  echo -e "\nNew etcd file...\n"
  cat "${cfg_file}"

  echo -e "\nRestarting etcd...\n"
  run_on_host "${restart_etcd_command}"
}

update_etcd
update_kubelet_env_file
update_kubelet_config_file
restart_host_kubelet
