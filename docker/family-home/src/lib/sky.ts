type Stop = [elevation: number, top: string, bottom: string, ink: "light" | "dark"];

// Sky colours keyed by sun elevation in degrees: night, blue hour, sunrise/sunset, day.
const stops: Stop[] = [
  [-18, "#0f1a2b", "#1f2e47", "light"],
  [-6, "#22325a", "#7a6a8e", "light"],
  [0, "#4d5f92", "#e3a48f", "light"],
  [8, "#7fa3cc", "#f2d3b3", "dark"],
  [25, "#8fbbe0", "#d9ebf2", "dark"],
];

const hex = (c: string) => [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16));
const mix = (a: string, b: string, t: number) =>
  `rgb(${hex(a).map((v, i) => Math.round(v + (hex(b)[i] - v) * t)).join(" ")})`;

export function sky(elevation = 20) {
  const upper = stops.findIndex(([e]) => e >= elevation);
  if (upper <= 0) {
    const [, top, bottom, ink] = stops[upper === 0 ? 0 : stops.length - 1];
    return { top, bottom, ink };
  }
  const [e0, t0, b0, ink0] = stops[upper - 1];
  const [e1, t1, b1] = stops[upper];
  const t = (elevation - e0) / (e1 - e0);
  return { top: mix(t0, t1, t), bottom: mix(b0, b1, t), ink: ink0 };
}
