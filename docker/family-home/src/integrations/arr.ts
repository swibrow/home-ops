import { cached, getJson } from "../lib/cache";
import { env } from "../lib/config";
import { addDays, isoDay } from "../lib/time";

type Image = { coverType: string; remoteUrl?: string };
type Episode = { id: number; title: string; seasonNumber: number; episodeNumber: number; airDateUtc?: string; hasFile: boolean; series: { title: string; images: Image[] } };
type Movie = { id: number; title: string; year: number; digitalRelease?: string; physicalRelease?: string; hasFile: boolean; images: Image[] };

export type Upcoming = { key: string; title: string; detail: string; date: Date; image?: string; ready: boolean };

const poster = (images: Image[]) => images.find((i) => i.coverType === "poster")?.remoteUrl;

const sonarr = { url: env("SONARR_URL"), key: env("SONARR_TOKEN") };
const radarr = { url: env("RADARR_URL"), key: env("RADARR_TOKEN") };

async function episodes(start: string, end: string): Promise<Upcoming[]> {
  if (!sonarr.url || !sonarr.key) return [];
  const list = await getJson<Episode[]>(`${sonarr.url}/api/v3/calendar?start=${start}&end=${end}&includeSeries=true`, {
    headers: { "X-Api-Key": sonarr.key },
  });
  return list.flatMap((e) =>
    e.airDateUtc
      ? [{ key: `tv-${e.id}`, title: e.series.title, detail: `S${e.seasonNumber} E${e.episodeNumber}`, date: new Date(e.airDateUtc), image: poster(e.series.images), ready: e.hasFile }]
      : [],
  );
}

async function movies(start: string, end: string): Promise<Upcoming[]> {
  if (!radarr.url || !radarr.key) return [];
  const list = await getJson<Movie[]>(`${radarr.url}/api/v3/calendar?start=${start}&end=${end}`, {
    headers: { "X-Api-Key": radarr.key },
  });
  return list.flatMap((m) => {
    const release = m.digitalRelease ?? m.physicalRelease;
    return release ? [{ key: `movie-${m.id}`, title: m.title, detail: "Film", date: new Date(release), image: poster(m.images), ready: m.hasFile }] : [];
  });
}

export const loadUpcoming = () =>
  sonarr.key || radarr.key
    ? cached("arr", 600, async () => {
        const start = isoDay();
        const end = isoDay(addDays(new Date(), 8));
        const all = (await Promise.all([episodes(start, end), movies(start, end)])).flat();
        return all.filter((u) => u.date >= new Date(`${start}T00:00:00Z`)).sort((a, b) => a.date.getTime() - b.date.getTime());
      })
    : undefined;
