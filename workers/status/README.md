# status.wibrow.dev

The public status page. A Cloudflare Worker, not a cluster workload — on
purpose: a status page hosted inside the thing it reports on cannot tell you
that the thing is down.

## How it works

```
Prometheus ──▶ kromgo ──▶ Worker ──▶ KV (last known good)
 infra:*        badges     render         │
                                          └──▶ status.wibrow.dev
```

- **Prometheus** records `infra:component:up` and the rollups above it
  (`kubernetes/apps/pitower/monitoring/infra-health/prometheusrule.yaml`).
- **kromgo** (`kubernetes/apps/pitower/networking/kromgo/values.yaml`) exposes a
  handful of those as public JSON endpoints. It is the only route by which
  `infra:*` leaves the cluster; Prometheus itself is never exposed.
- **This Worker** reads them server-side and writes the result to KV. Requests
  are served from KV, so on a healthy day no visitor request touches the
  cluster at all.
- **KV** holds the last successful reading. A failed refresh never overwrites
  it, so during an outage the page still renders — labelled with how old the
  reading is, and downgraded to "Status unknown" past five minutes.

The badge ids in `src/kromgo.ts` and the `config.badges` entries in kromgo's
values are one contract in two files; change them together. An id that drifts
renders as `unknown`, which is a safe failure but a silent one.

### What the page leads with

`infra:public:up_ratio` — the fraction of publicly exposed services that
answered **from the blackbox prober on ovh-vps**. From inside the LAN,
`*.wibrow.dev` resolves straight to the envoy-external LoadBalancer, so an
in-cluster probe stays green through a total tunnel outage. Only the external
vantage proves the path a visitor actually takes.

Internal health (`infra:overall:up`) is shown as a secondary signal. It is a
`min()` across every non-application tier, so it is deliberately unforgiving
and can read degraded while everything a visitor touches is fine. It can lower
the page's level, never raise it.

## Endpoints

| Path                | Response                                    |
| ------------------- | ------------------------------------------- |
| `/`                 | The status page (server-rendered, no JS)    |
| `/api/status.json`  | The same state as JSON                      |

## Local development

```shell
bun install
bun test          # pure logic: state derivation, fetch failure modes, escaping
bun run typecheck
bun run dev       # local Workers runtime + local KV
```

`bun run dev` points at the real `https://kromgo.wibrow.dev` by default. To
drive it from fixtures instead, pass `--var KROMGO_ORIGIN:http://127.0.0.1:8798`
and serve the badge ids from `src/kromgo.ts` on that port.

## First deploy

One-time setup, in order. **The ordering is load-bearing.**

1. Land the gatus move to `up.wibrow.dev` and let ArgoCD sync it. external-dns
   runs `policy: sync`, so it deletes the `status.wibrow.dev` CNAME it owned
   from the old HTTPRoute.
2. Confirm the CNAME is gone and the proxied `AAAA 100::` from
   `networking/external-dns/dnsendpoint-status.yaml` has replaced it. A Worker
   route only fires on proxied traffic, and it cannot bind a name the cluster
   still owns a record for.

   ```shell
   dig +short AAAA status.wibrow.dev @1.1.1.1
   dig +short CNAME status.wibrow.dev @1.1.1.1   # must be empty
   ```

3. Create the KV namespace and paste its id into `wrangler.jsonc`:

   ```shell
   bunx wrangler kv namespace create STATUS_SNAPSHOT
   ```

4. Deploy:

   ```shell
   bun run deploy
   ```

5. Prime KV so the first visitor does not pay for a cold fetch:

   ```shell
   curl -s https://status.wibrow.dev/api/status.json | jq .level
   ```

Afterwards, `.github/workflows/deploy-status-worker.yaml` handles deploys on
manual dispatch. It needs a `CLOUDFLARE_API_TOKEN` repository secret with
*Edit Cloudflare Workers* on the `wibrow.dev` zone. Add a `push` trigger scoped
to `workers/status/**` once the first deploy has succeeded.
