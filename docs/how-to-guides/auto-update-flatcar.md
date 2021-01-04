---
title: Auto-updating Flatcar Container Linux
weight: 10
---

## Introduction

At the moment, Lokomotive supports only [Flatcar Container Linux](https://www.flatcar-linux.org/) as
an underlying operating system for nodes. While Flatcar can keep itself up to date, when running
Kubernetes on top of it, we recommend using [Flatcar Linux Update Operator
(FLUO)](https://github.com/kinvolk/flatcar-linux-update-operator) to perform updates to avoid
rebooting too many nodes at a time, which could cause the outage for services.

FLUO is a supported Lokomotive component.

This guide will show how to install it and disable its
auto-update feature for specific nodes, which might be useful when you run services, which require
special care before shutting down (e.g. storage clusters).

## Prerequisites

- A Kubernetes cluster accessible via `kubectl` using Flatcar Container Linux for nodes.

## Steps

### Step 1: Disable auto-update on sensitive nodes

If you want to update the Flatcar OS of particular nodes manually in a controlled fashion, there is
a way to disable automatic updates. Disabling updates can come handy when the workloads run by these
machines are storage or ingress network related, where the applications cannot tolerate abrupt
reboot of node.

Please annotate the nodes with the following annotation:

```bash
kubectl annotate node <node name> "flatcar-linux-update.v1.flatcar-linux.net/reboot-paused=true"
```

### Step 2: Configure FLUO

Add the following content to your cluster configuration (e.g. in `fluo.lokocfg` file):

```tf
component "flatcar-linux-update-operator" {}
```

### Step 3: Install FLUO

Execute the following command to deploy the `flatcar-linux-update-operator` component:

```bash
lokoctl component apply flatcar-linux-update-operator
```

Verify the pods in the `reboot-coordinator` namespace are in the `Running` state (this may take a few
minutes):

```bash
kubectl -n reboot-coordinator get pods
```

### Step 4: Test installation

To test that it is working, you can SSH into a node and trigger an update check by running
`update_engine_client -check_for_update` or simulate a reboot is needed by running
`locksmithctl send-need-reboot`.
