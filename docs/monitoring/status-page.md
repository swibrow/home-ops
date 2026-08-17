# Status Page

`status.wibrow.dev` is the public status page. It runs as a Cloudflare Worker,
not as a cluster workload -- a status page hosted inside the thing it reports on
cannot tell you that the thing is down.

## The chain

```
Prometheus ──▶ kromgo ──▶ Worker ──▶ KV (last known good)
 infra:*        badges     render         │
                                          └──▶ status.wibrow.dev
```

| Piece | Where |
|:------|:------|
| Recording rules | `kubernetes/apps/pitower/monitoring/infra-health/prometheusrule.yaml` |
| Public metric endpoints | `kubernetes/apps/pitower/networking/kromgo/values.yaml` |
| Worker | `workers/status/` |
| Operator dashboard | Grafana, **Status → Infrastructure health** |
| Per-endpoint detail | Gatus, `up.wibrow.dev` |

Requests are served from KV, so on a healthy day no visitor request touches the
cluster at all. A refresh that fails never overwrites the stored snapshot, so
during an outage the page still renders -- labelled with the age of the reading,
and downgraded to "Status unknown" once that age passes five minutes.

The badge ids in `workers/status/src/kromgo.ts` and the `config.badges` entries
in kromgo's values are one contract split across two files. Change them
together; an id that drifts renders as `unknown`, which fails safely but
silently.

## The metric everything folds into

`infra:component:up{tier, component, exposure, scope}`, a ratio in `[0,1]`:

| Value | Meaning |
|:------|:--------|
| `1` | operational |
| `0` | down |
| `0 < v < 1` | degraded (k of n healthy) |
| absent | unknown -- no evidence either way |

Absent and zero are deliberately different. `infra:component:stale` exists so a
dead exporter alerts as a dead exporter rather than as a dead estate, and the
page says "N signals missing" rather than quietly counting them as healthy.

## What the page leads with

`infra:public:up_ratio` -- the fraction of publicly exposed services that
answered **from the blackbox prober on ovh-vps**.

This distinction is the whole point. From inside the LAN, `*.wibrow.dev`
resolves straight to the envoy-external LoadBalancer, so an in-cluster probe
reports green straight through a total tunnel, ISP or Cloudflare failure. Only
`scope="wan"` series have actually crossed the internet, the tunnel and the
gateway, which is why the rollup is restricted to them and reads empty rather
than optimistic when that vantage is quiet.

Internal health (`infra:overall:up`) is shown as a secondary signal. It is a
`min()` across every non-application tier, so it is unforgiving by design: one
degraded backup reads as degraded while everything a visitor touches is fine.
It can lower the page's level, never raise it.

## Deploying

See `workers/status/README.md`. The first deploy is manual and the ordering is
load-bearing: external-dns (`policy: sync`) must release the old
`status.wibrow.dev` CNAME and replace it with the proxied `AAAA 100::`
placeholder before a Worker route can bind the name.
