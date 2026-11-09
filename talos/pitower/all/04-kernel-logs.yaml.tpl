# Ships kmsg to monitoring/kernel-logs, so the lines before a hang or a panic
# outlive the node. UDP sends each line as it is written; a frozen kernel takes
# TCP's unsent buffer with it.
#
# Talos records carry no hostname and the sender's address can't stand in: the
# socket opens at boot, before Cilium, so its packets reach the receiver through
# the L2 announcer, SNATed to that node's address. Each node sends to its own
# port instead, 5100 plus the last octet of its IP.
---
apiVersion: v1alpha1
kind: KmsgLogConfig
name: kernel-logs
url: udp://10.20.10.241:{{ add 5100 (.Node.IP.String | splitList "." | last) }}/
