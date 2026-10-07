---
title: Cilium CNI
---

# Cilium CNI

Cilium (Helm chart `1.20.2`) is the CNI for the cluster and replaces kube-proxy. It provides eBPF service handling, LoadBalancer IPs (LB-IPAM, announced over L2 and BGP), native routing for dual-stack pod traffic, and Hubble for observability. Multus runs alongside it for secondary pod interfaces.

Manifests live in `kubernetes/apps/pitower/kube-system/cilium/`:

| Path | Content |
|:-----|:--------|
| `operator/values.yaml` | Helm values |
| `operator/httproute-hubble.yaml` | Hubble UI route |
| `config/cilium-l2.yaml` | `CiliumL2AnnouncementPolicy` and `CiliumLoadBalancerIPPool` |
| `config/cilium-bgp.yaml` | BGP cluster config, peer configs and advertisements |

## Why Cilium

| Concern | Traditional Stack | Cilium |
|:--------|:-----------------|:-------|
| CNI | Flannel / Calico | Cilium (eBPF) |
| Service proxy | kube-proxy (iptables) | Cilium (eBPF) |
| LoadBalancer IPs | MetalLB (L2/BGP) | LB-IPAM + L2 announcements + BGP control plane |
| Network observability | Third-party tools | Hubble (built-in) |

## Key Helm Values

```yaml title="kubernetes/apps/pitower/kube-system/cilium/operator/values.yaml (excerpt)"
cluster:
  name: pitower
  id: 1

kubeProxyReplacement: true
kubeProxyReplacementHealthzBindAddr: 0.0.0.0:10256
k8sServiceHost: 127.0.0.1
k8sServicePort: 7445

routingMode: native
autoDirectNodeRoutes: true
endpointRoutes:
  enabled: true
ipam:
  mode: kubernetes
ipv4NativeRoutingCIDR: 10.244.0.0/16
ipv6:
  enabled: true
ipv6NativeRoutingCIDR: fd10:244::/56

bpf:
  masquerade: true
bgpControlPlane:
  enabled: true
l2announcements:
  enabled: true
loadBalancer:
  algorithm: maglev
  mode: snat
localRedirectPolicy: true

# Multus owns 00-multus.conf in /etc/cni/net.d
cni:
  exclusive: false

# KubeVirt VM traffic never passes through connect()/sendmsg()
socketLB:
  hostNamespaceOnly: true

envoy:
  enabled: false
gatewayAPI:
  enabled: false
```

Cilium's own Envoy and Gateway API support are disabled; ingress is handled by [Envoy Gateway](envoy-gateway.md).

## Kube-Proxy Replacement

> [!NOTE]
> **Talos Linux Integration**
>
> kube-proxy is disabled in the Talos config. `k8sServiceHost: 127.0.0.1` and `k8sServicePort: 7445` point Cilium at KubePrism, Talos's local API server proxy, so it can reach the API without kube-proxy from the first boot.

All ClusterIP, NodePort and LoadBalancer handling is done in eBPF. Load balancing uses Maglev consistent hashing in SNAT mode.

`socketLB.hostNamespaceOnly: true` keeps socket-level service translation to the host namespace, so pod and KubeVirt VM traffic is translated at tc level instead.

## Native Routing and IPv6

Pod traffic is routed without encapsulation. `autoDirectNodeRoutes` installs routes to other nodes' pod CIDRs, and each node's pod CIDR is also advertised to the gateway over BGP, so the LAN reaches pod IPs directly (except on `worker-ai-01`, which does not peer).

The cluster is dual-stack with IPv4 primary:

| | IPv4 | IPv6 |
|:--|:-----|:-----|
| Pods | `10.244.0.0/16` (a `/24` per node) | `fd10:244::/56` ULA (a `/64` per node) |
| Services | `10.96.0.0/12` | `fd10:96::/112` |
| LoadBalancer pool | `10.20.10.128`-`255` | `2a02:16a:2a0a:3::/112` |

Pod subnets come from the Talos `KubeNetworkConfig` (`talos/pitower/all/03-network.yaml.tpl`). Pod egress to anything outside the native routing CIDRs is masqueraded to the node address with BPF masquerade; ULA is not routable upstream. Services stay IPv4-only unless they set `ipFamilyPolicy`.

> [!WARNING]
> **Pod CIDRs are immutable**
>
> `spec.podCIDRs` cannot change on an existing Node. A node registered before a pod subnet change keeps its old CIDRs until its Node object is deleted and kubelet restarted.

## L2 Announcements

The pool sits inside VLAN 20, so on-VLAN clients ARP for the VIPs. Every Linux node except `worker-ai-01` (often booted into another OS) can hold the lease:

```yaml title="kubernetes/apps/pitower/kube-system/cilium/config/cilium-l2.yaml"
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
metadata:
  name: policy
spec:
  loadBalancerIPs: true
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
    matchExpressions:
      - key: kubernetes.io/hostname
        operator: NotIn
        values: [worker-ai-01]
---
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: pool
spec:
  allowFirstLastIPs: "Yes"
  blocks:
    - start: 10.20.10.128
      stop: 10.20.10.255
    - cidr: 2a02:16a:2a0a:3::/112
```

See [Load Balancers](load-balancers.md) for allocations.

## BGP

Cilium peers with the UniFi Cloud Gateway (UCG Fiber) from every node except `worker-ai-01`:

| Setting | Value |
|:--------|:------|
| Cluster ASN | `64513` |
| Gateway ASN | `64512` |
| IPv4 peer | `ucg`, `10.20.0.1` |
| IPv6 peer | `ucg-v6`, `2a02:16a:2a0a:2::1` |
| Timers | keepalive 3s, hold 9s |
| Advertised | LoadBalancer IPs (every Service) and each node's pod CIDR, per family |

IPv6 routes use their own session because over the IPv4 one the next hop would be an IPv4-mapped address the gateway cannot use.

The gateway side is `terraform/unifi/frr-bgp.conf`. The UniFi provider has no BGP resource, so it is pushed with `mise run unifi:bgp-upload` from `terraform/`. It lists each node IP as an IPv4 neighbor (IPv6 peers are accepted by `bgp listen range 2a02:16a:2a0a:2::/64`), only accepts `/32`s from the LB pool, `/24` pod CIDRs (and the IPv6 equivalents), and sends nothing back. Adding or renumbering a node means editing it and re-running the task.

## Multus

Multus (thick plugin, `kube-system/multus`, `v4.3.1`) adds secondary pod interfaces; Cilium stays the primary CNI, which is why `cni.exclusive` is `false`. An init container copies the `macvlan` and `static` CNI plugins onto the host, since Talos does not ship them.

| NetworkAttachmentDefinition | Network | Parent |
|:----------------------------|:--------|:-------|
| `kube-system/vlan20` | VLAN 20 | Each node's default-route link |
| `networking/lan` | Untagged LAN | `enp0s25` (worker-05/06 only), used by netboot |

Attachments use macvlan with static IPAM, so each pod picks its own address:

```yaml
k8s.v1.cni.cncf.io/networks: '[{"name":"vlan20","namespace":"kube-system","ips":["10.20.x.y/16"]}]'
```

Keep those addresses outside the DHCP scope and the LB pool.

> [!WARNING]
> **Multus caveats**
>
> - Traffic on `net1` bypasses Cilium policy and Hubble.
> - A pod cannot reach its own node over macvlan.
> - Normal cluster pods cannot reach a pod's `net1` address from another subnet (asymmetric return path).
> - If pods lose `net1` after a Cilium rollout, check `/etc/cni/net.d` for `00-multus.conf.cilium_bak` and restart that node's Multus pod.

## Hubble

Hubble relay and UI are enabled, with these flow metrics:

```yaml
hubble:
  metrics:
    enabled:
      - dns:query;ignoreAAAA
      - drop
      - tcp
      - flow
      - port-distribution
      - icmp
      - http
```

The UI is on `envoy-internal` at `https://hubble.wibrow.dev`. Agent, operator, relay and Hubble metrics are scraped via ServiceMonitors, and dashboards are provisioned into the Grafana `Networking` folder.

## Troubleshooting

```bash
# Agent status
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium status --brief

# BGP sessions (both should be "established")
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium bgp peers

# LB pool and L2 policy
kubectl get ciliumloadbalancerippools,ciliuml2announcementpolicies
kubectl get leases -n kube-system | grep cilium-l2

# Service table
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium service list

# Live flows
kubectl -n kube-system exec ds/cilium -c cilium-agent -- hubble observe --follow
kubectl -n kube-system exec ds/cilium -c cilium-agent -- hubble observe --namespace networking
```
