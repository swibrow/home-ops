import { cached, getJson } from "../lib/cache";
import { config, env } from "../lib/config";

type Item = {
  Id: string;
  Name: string;
  Type: string;
  SeriesName?: string;
  SeriesId?: string;
  SeriesPrimaryImageTag?: string;
  ProductionYear?: number;
  ParentIndexNumber?: number;
  IndexNumber?: number;
  ImageTags?: { Primary?: string };
  UserData?: { PlayedPercentage?: number };
};

export type Tile = { id: string; title: string; detail?: string; image?: string; href: string; progress?: number };

const api = env("JELLYFIN_URL");
const token = env("JELLYFIN_TOKEN");
const { url, userId } = config.jellyfin;
const headers = { Authorization: `MediaBrowser Token="${token}"` };

const tile = (item: Item): Tile => {
  const episode = item.Type === "Episode";
  const posterId = episode && item.SeriesPrimaryImageTag ? item.SeriesId : item.ImageTags?.Primary ? item.Id : undefined;
  return {
    id: item.Id,
    title: episode ? item.SeriesName ?? item.Name : item.Name,
    detail: episode ? `S${item.ParentIndexNumber ?? "?"} E${item.IndexNumber ?? "?"}: ${item.Name}` : item.ProductionYear?.toString(),
    image: posterId && `${url}/Items/${posterId}/Images/Primary?fillHeight=360&quality=85`,
    href: `${url}/web/#/details?id=${item.Id}`,
    progress: item.UserData?.PlayedPercentage,
  };
};

export const loadJellyfin = () =>
  api && token
    ? cached("jellyfin", 120, async () => {
        const [resume, latest] = await Promise.all([
          getJson<{ Items: Item[] }>(`${api}/UserItems/Resume?userId=${userId}&limit=8&mediaTypes=Video`, { headers }),
          getJson<Item[]>(`${api}/Items/Latest?userId=${userId}&limit=12`, { headers }),
        ]);
        return { resume: resume.Items.map(tile), latest: latest.map(tile) };
      })
    : undefined;
