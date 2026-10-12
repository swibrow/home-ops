# GPU Benchmarks

How the RTX 3090 Ti and RTX PRO 4000 Blackwell on worker-ai-01 were benchmarked against each other with Qwen3.8-27B in October 2026, so the runs can be repeated for the next card or model. The write-up with the full results is the blog post [RTX 3090 Ti vs RTX PRO 4000 Blackwell for local LLMs](https://wibrow.dev/posts/rtx-3090-ti-vs-rtx-pro-4000/).

Everything runs as one-off Jobs in the `ai` namespace against the `llmkube-model-cache` PVC, outside GitOps. Nothing here is synced by ArgoCD.

## Setup

| | |
|---|---|
| Node | worker-ai-01: Ryzen 7 9700X, 64 GB, both GPUs at PCIe x8 through the CPU (`nvidia-smi topo -m` shows `PHB`, no NVLink) |
| Driver | 595.91.07 (CUDA 13.2) |
| llama.cpp | `ghcr.io/ggml-org/llama.cpp:full-cuda-b11096` (CUDA 12 build, has `llama-bench` and `llama-batched-bench`) |
| Models | unsloth `Qwen3.8-27B-GGUF`: UD-Q4_K_M, Q4_0, UD-Q5_K_M, Q8_0 (dual-card only) |
| Common flags | `-ngl 99 -fa on -ctk q8_0 -ctv q8_0` |
| Power and clocks | DCGM exporter in Prometheus, per card by `modelName` |

## Headline results

UD-Q4_K_M, single user, empty context, t/s:

| | 3090 Ti 450W | 3090 Ti 300W | 3090 Ti 145W | PRO 4000 145W | Both, layer split 50/50 (3090 Ti at 300W) |
|---|---:|---:|---:|---:|---:|
| Prompt 2048 | 1591 | 1258 | 309 | 1234 | 1947 |
| Generation | 47.5 | 36.5 | 11.3 | 32.1 | 39.3 |
| J per generated token | 9.5 | 8.3 | - | 4.5 | - |

Idle draw: 3090 Ti 22-31W, PRO 4000 about 4W. Raw jsonl for every run is on the PVC under `/models/bench/results/<run>/`.

## Running it

### 1. Pin a card

The shared `llmkube-gpu` template takes any GPU. Benchmarks need a specific card, so each gets its own `ResourceClaimTemplate` selected by product name (attribute values from `kubectl get resourceslices -o yaml`):

```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: bench-pro4000   # bench-3090ti: 'NVIDIA GeForce RTX 3090 Ti'
  namespace: ai
spec:
  spec:
    devices:
      requests:
        - name: gpu
          exactly:
            deviceClassName: gpu.nvidia.com
            selectors:
              - cel:
                  expression: device.attributes['gpu.nvidia.com'].productName == 'NVIDIA RTX PRO 4000 Blackwell'
---
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: bench-both
  namespace: ai
spec:
  spec:
    devices:
      requests:
        - name: gpu
          exactly:
            deviceClassName: gpu.nvidia.com
            allocationMode: ExactCount
            count: 2
```

### 2. Fetch the models

A curl Job with the existing `huggingface` secret, writing to `/models/bench/` on the model cache. Hugging Face throttled to about 8 MB/s partway through a 50 GB pull, so leave time.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: bench-fetch-models
  namespace: ai
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: OnFailure
      nodeSelector:
        kubernetes.io/hostname: worker-ai-01
      tolerations:
        - {key: dedicated, operator: Equal, value: gpu, effect: NoSchedule}
      containers:
        - name: fetch
          image: docker.io/curlimages/curl:8.18.0
          command: ["/bin/sh", "-ec"]
          args:
            - |
              mkdir -p /models/bench && cd /models/bench
              for f in Qwen3.8-27B-UD-Q4_K_M.gguf Qwen3.8-27B-Q4_0.gguf Qwen3.8-27B-UD-Q5_K_M.gguf; do
                [ -s "$f" ] && continue
                curl -fL --retry 5 -H "Authorization: Bearer $HF_TOKEN" -o "$f.part" \
                  "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/$f"
                mv "$f.part" "$f"
              done
          envFrom:
            - secretRef: {name: huggingface}
          volumeMounts:
            - {name: models, mountPath: /models}
      volumes:
        - name: models
          persistentVolumeClaim: {claimName: llmkube-model-cache}
```

### 3. Benchmark Job

`bench-job.tmpl.yaml`. `GPU` is replaced with `3090ti`, `pro4000` or `both`, and `RUNID` with the run name:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: llama-bench-GPU
  namespace: ai
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      nodeSelector:
        kubernetes.io/hostname: worker-ai-01
      tolerations:
        - {key: dedicated, operator: Equal, value: gpu, effect: NoSchedule}
      resourceClaims:
        - name: gpu
          resourceClaimTemplateName: bench-GPU
      containers:
        - name: bench
          image: ghcr.io/ggml-org/llama.cpp:full-cuda-b11096
          command: ["/bin/bash", "-ec"]
          args:
            - |
              out=/models/bench/results/$RUN; mkdir -p "$out"
              for m in Qwen3.8-27B-UD-Q4_K_M Qwen3.8-27B-Q4_0 Qwen3.8-27B-UD-Q5_K_M; do
                echo "start $m $(date +%s)" | tee -a "$out/GPU-times.txt"
                /app/llama-bench -m /models/bench/$m.gguf -ngl 99 -fa on -ctk q8_0 -ctv q8_0 \
                  -p 512,2048 -n 128 -d 0,4096,16384,32768 -r 5 -o jsonl | tee "$out/GPU-$m.jsonl"
                echo "end $m $(date +%s)" | tee -a "$out/GPU-times.txt"
              done
              /app/llama-batched-bench -m /models/bench/Qwen3.8-27B-UD-Q4_K_M.gguf -ngl 99 -fa on \
                -ctk q8_0 -ctv q8_0 -c 32768 -npp 512,2048 -ntg 128 -npl 1,2,4,8 --output-format jsonl \
                | tee "$out/GPU-batched.jsonl"
          env:
            - {name: RUN, value: "RUNID"}
          resources:
            claims: [{name: gpu}]
            requests: {cpu: "4", memory: 8Gi}
            limits: {memory: 16Gi}
          volumeMounts:
            - {name: models, mountPath: /models}
      volumes:
        - name: models
          persistentVolumeClaim: {claimName: llmkube-model-cache}
```

Variants swap the `args` body:

- **Generation-only power** (clean J/token): `llama-bench -p 0 -n 256 -r 20`, then `echo "tgend $(date +%s)"`. Take DCGM power averaged over the last 60s before `tgend`, so model load and prompt processing are excluded.
- **Both cards**: claim `bench-both`, set `CUDA_DEVICE_ORDER=PCI_BUS_ID` so CUDA0 is the 3090 Ti, and run each split mode as its own `llama-bench` call with `|| echo FAILED` so one crash doesn't end the Job: `-sm layer -ts 1/1`, `-sm layer -ts 3/2`, `-sm row`, `-sm tensor`.
- **Qwen3.8-Flash-Next (MoE, not run yet)**: mirror production with `-ncmoe 37 -ot per_layer_token_embd=CPU -t 12`, memory request 40Gi and limit 56Gi (the CPU-side experts live in page cache inside the pod's limit), and run an untimed warm-up first so the first card doesn't pay to page 46 GB in from disk.

### 4. Runner

`run.sh <3090ti|pro4000|both> [run-id]`, with `TMPL=<file>` to pick a variant. It waits for either `Complete` or `Failed`; `kubectl wait --for=condition=complete` alone hangs until its timeout on a failed Job.

```bash
#!/usr/bin/env bash
set -euo pipefail
gpu=$1; run=${2:-$(date +%Y%m%d-%H%M)}
cd "$(dirname "$0")"
kubectl -n ai delete job llama-bench-$gpu --ignore-not-found --wait
sed -e "s/GPU/$gpu/g" -e "s/RUNID/$run/" ${TMPL:-bench-job.tmpl.yaml} | kubectl apply -f -
until s=$(kubectl -n ai get job llama-bench-$gpu -o jsonpath='{.status.conditions[*].type}') && [[ $s =~ Complete|Failed ]]; do sleep 20; done
kubectl -n ai logs job/llama-bench-$gpu > "results-$gpu-$run.log"
[[ $s =~ Complete ]]
```

Run cards one after the other, not in parallel, so they don't share CPU and PCIe.

### 5. Power limits

The 3090 Ti's limit comes from the `nvidia-power-limit` DaemonSet (300W). It applies once per driver bind, so a one-off change holds until the pod restarts or the card rebinds:

```bash
p=$(kubectl -n system get pods -l app.kubernetes.io/name=nvidia-power-limit -o name | tail -1)
kubectl -n system exec $p -- nvidia-smi -i 0000:01:00.0 -pl 450
# ... run ...
kubectl -n system exec $p -- nvidia-smi -i 0000:01:00.0 -pl 300
```

Patching the DaemonSet's `POWER_LIMIT_WATTS` does not stick: ArgoCD's automated sync re-applied `main` within seconds even with `selfHeal: false`.

### 6. Report

`report.py` parses the Job logs (llama-bench jsonl plus the `start`/`end` markers) and pulls average and max power, max temperature and average SM clock per quant run from Prometheus. Port-forward Prometheus to `localhost:19090` first, then pass `label=gpu:run` pairs:

```bash
python3 -I report.py "3090 Ti @450W=3090ti:w450" "3090 Ti @300W=3090ti:r2" "PRO 4000=pro4000:r2"
```

```python
import json, re, sys, urllib.parse, urllib.request
from pathlib import Path

HERE = Path(__file__).parent
PROM = "http://localhost:19090/api/v1/query"
PRODUCT = {"3090ti": "NVIDIA GeForce RTX 3090 Ti", "pro4000": "NVIDIA RTX PRO 4000 Blackwell"}
QUANT = {"Q4_K - Medium": "UD-Q4_K_M", "Q4_0": "Q4_0", "Q5_K - Medium": "UD-Q5_K_M"}


def prom(expr, at):
    url = PROM + "?" + urllib.parse.urlencode({"query": expr, "time": at})
    res = json.load(urllib.request.urlopen(url))["data"]["result"]
    return float(res[0]["value"][1]) if res else float("nan")


def load(gpu, run):
    text = (HERE / f"results-{gpu}-{run}.log").read_text()
    rows = [json.loads(l) for l in text.splitlines() if l.startswith("{")]
    bench = [r for r in rows if "avg_ts" in r]
    batched = [r for r in rows if "speed_tg" in r]
    windows = {m: (int(s), int(e)) for m, s, e in re.findall(r"^start Qwen3\.8-27B-(\S+) (\d+)$.*?^end Qwen3\.8-27B-\1 (\d+)$", text, re.S | re.M)}
    return bench, batched, windows


def telemetry(gpu, start, end):
    sel = f'{{modelName="{PRODUCT[gpu]}"}}'
    rng = f"[{end - start}s]"
    return {
        "avg_w": prom(f"avg_over_time(DCGM_FI_DEV_POWER_USAGE{sel}{rng})", end),
        "max_w": prom(f"max_over_time(DCGM_FI_DEV_POWER_USAGE{sel}{rng})", end),
        "max_c": prom(f"max_over_time(DCGM_FI_DEV_GPU_TEMP{sel}{rng})", end),
        "avg_mhz": prom(f"avg_over_time(DCGM_FI_DEV_SM_CLOCK{sel}{rng})", end),
    }


def main():
    cards = [(label, *spec.split(":")) for label, spec in (a.split("=") for a in sys.argv[1:])]
    data = {label: load(gpu, run) for label, gpu, run in cards}
    labels = [l for l, _, _ in cards]

    print("## Throughput (llama-bench, t/s, mean of 5)\n")
    print("| Quant | Test | Depth | " + " | ".join(labels) + " |")
    print("|---|---|---:|" + "---:|" * len(labels))
    keys = [(QUANT[r["model_type"].split(" ", 2)[2]], f"pp{r['n_prompt']}" if r["n_prompt"] else f"tg{r['n_gen']}", r["n_depth"]) for r in data[labels[0]][0]]
    for i, (q, t, d) in enumerate(keys):
        cells = [f"{data[l][0][i]['avg_ts']:.1f} ± {data[l][0][i]['stddev_ts']:.1f}" for l in labels]
        print(f"| {q} | {t} | {d} | " + " | ".join(cells) + " |")

    print("\n## Concurrency (llama-batched-bench, UD-Q4_K_M, total t/s)\n")
    print("| Prompt | Parallel | " + " | ".join(f"{l} pp | {l} tg" for l in labels) + " |")
    print("|---:|---:|" + "---:|---:|" * len(labels))
    for i, r in enumerate(data[labels[0]][1]):
        cells = [f"{data[l][1][i]['speed_pp']:.0f} | {data[l][1][i]['speed_tg']:.1f}" for l in labels]
        print(f"| {r['pp']} | {r['pl']} | " + " | ".join(cells) + " |")

    print("\n## Power and efficiency per quant run (DCGM)\n")
    print("| Card | Quant | Avg W | Max W | Max °C | Avg SM MHz | tg128 @0 t/s | tg t/s per avg W |")
    print("|---|---|---:|---:|---:|---:|---:|---:|")
    for label, gpu, _ in cards:
        bench, _, windows = data[label]
        for quant, (s, e) in windows.items():
            t = telemetry(gpu, s, e)
            tg = next(r["avg_ts"] for r in bench if QUANT[r["model_type"].split(" ", 2)[2]] == quant and r["n_gen"] and r["n_depth"] == 0)
            print(f"| {label} | {quant} | {t['avg_w']:.0f} | {t['max_w']:.0f} | {t['max_c']:.0f} | {t['avg_mhz']:.0f} | {tg:.1f} | {tg / t['avg_w']:.3f} |")


main()
```

### 7. Grafana screenshots

The LLM Inference dashboard renders through Grafana's image renderer over a port-forward, authenticated with `grafana-admin-secret` (`grafana-admin-credentials` returns 401). Take run windows from `kube_pod_start_time` / `kube_pod_completion_time` for the `llama-bench-*` pods and pad them by about 15s:

```bash
curl -u "$user:$pass" -o run.png "localhost:13000/render/d/llm-inference/llm-inference?orgId=1&from=<ms>&to=<ms>&width=1600&height=2400&kiosk=true&tz=Europe%2FZurich&theme=dark"
```

Only the GPU row has data for llama-bench runs; the token panels read `llama-server` metrics. The GPU panels sum power and average utilisation across both cards, so a single-card run shows the idle card's draw and tops out at 50% utilisation.

## Gotchas

- **The container must reference the claim.** A pod-level `resourceClaims` entry without `resources.claims: [{name: gpu}]` on the container gets no GPU, and llama.cpp silently falls back to the CPU (`"backends": "CPU"`, empty `gpu_info` in the jsonl). Check the first result line before waiting for the rest.
- **No `nvidia-smi` in DRA containers.** The claim injects the device but not the utilities; use DCGM for power and clocks.
- **`full-cuda13-*` images need a CUDA 13.4 driver.** The node's 595.91 driver supports 13.2, so stick to the CUDA 12 build.
- **The power-limit DaemonSet must target one card.** `nvidia-smi -pl` without `-i` hits every GPU; the PRO 4000 only accepts 100-145W, so the command failed and looped every 10s until it was scoped with `-i "$GPU_PCI_ADDRESS"`.
- **DCGM lags one scrape.** Back-to-back runs show a sample of the previous run at the start of the next window; right after a run, the "current" power can be stale too.
- **Row and tensor split crash with Qwen3.8 on this build.** `-sm row` fails to load the model and `-sm tensor` hits a CUDA error in the first decode. Layer split works.
- **The 3090 Ti collapses at 145W.** SM clock falls to about 300 MHz and it overshoots to 168W; do not use it as an "equal power" comparison without saying so.
- **zsh and `[[ $s =~ a|b ]]`** is a parse error; wrap wait loops in `bash -c`.
