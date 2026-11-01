import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, rename, writeFile } from "node:fs/promises";
import http from "node:http";
import https from "node:https";
import { join } from "node:path";
import { env } from "../lib/config";
import type { Daypart } from "./homeassistant";

const base = env("COMFYUI_URL");
// The KEDA interceptor routes by Host, and fetch drops a Host header, hence node:http.
const host = env("COMFYUI_HOST");
export const sceneDir = join(process.env.DATA_DIR ?? "./data", "scenes");

const kinds: Record<string, string> = {
  sunny: "clear",
  "clear-night": "clear",
  partlycloudy: "partlycloudy",
  cloudy: "cloudy",
  windy: "cloudy",
  "windy-variant": "cloudy",
  exceptional: "cloudy",
  fog: "fog",
  rainy: "rain",
  pouring: "rain",
  lightning: "storm",
  "lightning-rainy": "storm",
  hail: "storm",
  snowy: "snow",
  "snowy-rainy": "snow",
};

const skies: Record<string, string> = {
  clear: "Completely clear cloudless sky, crisp and bright, not a single cloud",
  partlycloudy: "Partly cloudy: two or three distinct puffy white clouds with open clear sky around them",
  cloudy: "Fully overcast: a thick unbroken blanket of heavy grey cloud covering the whole sky",
  fog: "Dense fog: thick pale mist hiding the hills, everything soft, white and hazy",
  rain: "Rain: dark grey rain clouds with clearly visible long slanted rain streaks pouring down onto the hills",
  storm: "Thunderstorm: towering dark storm clouds, a bright jagged lightning bolt striking down, heavy rain streaks",
  snow: "Snowfall: many large white snowflakes falling from a pale grey sky, hills covered in white snow",
};

const light: Record<Daypart, string> = {
  night: "at night, deep navy blue sky, dark tones, small stars wherever the sky is clear",
  dawn: "at dawn, soft pale peach and lavender light low on the horizon",
  day: "in the daytime, bright natural daylight",
  dusk: "at dusk, warm orange and violet glow low on the horizon fading into deep blue",
};

// The scenes are cropped and crossfaded side by side, so the weather stays in the middle
// and the horizon at one height.
const style =
  "flat vector illustration, minimal layered shapes, muted harmonious palette, wide open sky filling most of the frame, the weather centred in the middle of the frame and fading out towards the left and right edges, low distant alpine hills along the bottom edge at a constant height, calm, painterly poster art";
const negative =
  "text, letters, watermark, signature, people, person, animals, buildings, sun, moon, photo, photorealistic, blurry, noisy, oversaturated, frame, border, cropped clouds";

// Wan 2.2 TI2V-5B is a video model; one frame of text-to-video is a still.
const workflow = (prompt: string) => ({
  1: { class_type: "UNETLoader", inputs: { unet_name: "wan2.2_ti2v_5B_fp16.safetensors", weight_dtype: "default" } },
  2: { class_type: "CLIPLoader", inputs: { clip_name: "umt5_xxl_fp8_e4m3fn_scaled.safetensors", type: "wan" } },
  3: { class_type: "VAELoader", inputs: { vae_name: "wan2.2_vae.safetensors" } },
  4: { class_type: "CLIPTextEncode", inputs: { clip: ["2", 0], text: prompt } },
  5: { class_type: "CLIPTextEncode", inputs: { clip: ["2", 0], text: negative } },
  6: { class_type: "Wan22ImageToVideoLatent", inputs: { vae: ["3", 0], width: 832, height: 480, length: 1, batch_size: 1 } },
  7: { class_type: "ModelSamplingSD3", inputs: { model: ["1", 0], shift: 8 } },
  8: {
    class_type: "KSampler",
    inputs: {
      model: ["7", 0],
      positive: ["4", 0],
      negative: ["5", 0],
      latent_image: ["6", 0],
      seed: 7,
      steps: 20,
      cfg: 5,
      sampler_name: "euler",
      scheduler: "simple",
      denoise: 1,
    },
  },
  9: { class_type: "VAEDecode", inputs: { samples: ["8", 0], vae: ["3", 0] } },
  10: { class_type: "SaveImage", inputs: { images: ["9", 0], filename_prefix: "family-home/sky" } },
});

type Workflow = ReturnType<typeof workflow>;

const request = (path: string, body?: object, timeout = 30_000) =>
  new Promise<Buffer>((resolve, reject) => {
    const target = new URL(path, base);
    const req = (target.protocol === "https:" ? https : http).request(
      target,
      { method: body ? "POST" : "GET", headers: { "Content-Type": "application/json", ...(host && { Host: host }) } },
      (res) => {
        const chunks: Buffer[] = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () =>
          res.statusCode! < 300 ? resolve(Buffer.concat(chunks)) : reject(new Error(`${target.pathname} returned ${res.statusCode}`)),
        );
        res.on("error", reject);
      },
    );
    req.setTimeout(timeout, () => req.destroy(new Error(`${target.pathname} timed out`)));
    req.on("error", reject);
    req.end(body && JSON.stringify(body));
  });

async function render(file: string, graph: Workflow) {
  // The interceptor holds the first request while the pod scales up from zero.
  const { prompt_id } = JSON.parse(String(await request("/prompt", { prompt: graph }, 330_000)));
  for (const deadline = Date.now() + 600_000; Date.now() < deadline; ) {
    await new Promise((resolve) => setTimeout(resolve, 2000));
    const entry = JSON.parse(String(await request(`/history/${prompt_id}`)))[prompt_id];
    if (!entry) continue;
    const image = entry.outputs?.["10"]?.images?.[0];
    if (!image) throw new Error(`render of ${file} failed: ${entry.status?.status_str}`);
    const png = await request(`/view?${new URLSearchParams(image)}`);
    await mkdir(sceneDir, { recursive: true });
    await writeFile(join(sceneDir, `${file}.tmp`), png);
    await rename(join(sceneDir, `${file}.tmp`), join(sceneDir, file));
    return;
  }
  throw new Error(`render of ${file} timed out`);
}

const waiting = new Map<string, Workflow>();
const ready = new Set<string>();
let busy = false;
let pausedUntil = 0;

// One render at a time, since the GPU is shared; a failure pauses everything so a down
// ComfyUI is retried by a later page render rather than in a loop.
async function drain() {
  busy = true;
  for (const [file, graph] of waiting) {
    try {
      const started = Date.now();
      await render(file, graph);
      console.log(`[comfyui] rendered ${file} in ${Math.round((Date.now() - started) / 1000)}s`);
      waiting.delete(file);
    } catch (error) {
      console.error("[comfyui]", error instanceof Error ? error.message : error);
      pausedUntil = Date.now() + 600_000;
      waiting.clear();
    }
  }
  busy = false;
}

// The file name for a Home Assistant condition at a time of day, or undefined while it is
// still being painted. Names carry a hash of the workflow, so a new prompt paints anew.
export function scene(condition: string, daypart: Daypart) {
  const kind = kinds[condition] ?? "cloudy";
  const graph = workflow(`${skies[kind]} ${light[daypart]}, ${style}`);
  const file = `${kind}-${daypart}-${createHash("sha1").update(JSON.stringify(graph)).digest("hex").slice(0, 8)}.png`;
  if (ready.has(file)) return file;
  if (existsSync(join(sceneDir, file))) {
    ready.add(file);
    return file;
  }
  if (base && !waiting.has(file) && Date.now() > pausedUntil) {
    waiting.set(file, graph);
    if (!busy) void drain();
  }
  return undefined;
}
