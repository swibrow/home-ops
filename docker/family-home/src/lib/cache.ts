const entries = new Map<string, { at: number; value: Promise<unknown> }>();

// Failed loads are kept only briefly so a down service is retried soon after it recovers.
export function cached<T>(key: string, ttlSeconds: number, load: () => Promise<T>): Promise<T> {
  const hit = entries.get(key);
  if (hit && Date.now() - hit.at < ttlSeconds * 1000) return hit.value as Promise<T>;
  const value = load();
  entries.set(key, { at: Date.now(), value });
  value.catch(() => entries.set(key, { at: Date.now() - (ttlSeconds - 15) * 1000, value }));
  return value;
}

export async function getJson<T>(url: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(url, { ...init, signal: AbortSignal.timeout(4000) });
  if (!res.ok) throw new Error(`${url} returned ${res.status}`);
  return res.json() as Promise<T>;
}

export async function settle<T>(name: string, promise: Promise<T> | undefined): Promise<T | undefined> {
  try {
    return await promise;
  } catch (error) {
    console.error(`[${name}]`, error instanceof Error ? error.message : error);
    return undefined;
  }
}

export function forget(key: string) {
  entries.delete(key);
}
