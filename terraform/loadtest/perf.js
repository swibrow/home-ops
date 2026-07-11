// Raw throughput test — GET the target root. Load controlled via CLI flags
// (e.g. k6 run -u 10 -d 20s, or --stage 30s:50,1m:200). TARGET via env.
import http from 'k6/http';
import { check } from 'k6';

const TARGET = __ENV.TARGET;

export default function () {
  const res = http.get(TARGET, { headers: { 'User-Agent': 'k6-perf/1.0' } });
  check(res, { 'status < 500': (r) => r.status > 0 && r.status < 500 });
}
