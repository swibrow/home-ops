// Attack-pattern test for the Cloudflare/envoy-external path: scanner UA +
// SQLi/XSS/traversal + probing 404s from one IP. Lights up Coraza (per-request
// CRS detections) and should trip CrowdSec http-probing / http-bad-user-agent
// scenarios -> a ban decision for this source IP. TARGET via env.
import http from 'k6/http';
import { check } from 'k6';

const TARGET = __ENV.TARGET;

const PATHS = [
  "/?id=1%27%20OR%20%271%27=%271",     // SQLi
  "/?q=<script>alert(1)</script>",      // XSS
  "/../../../../etc/passwd",            // path traversal
  "/wp-login.php", "/wp-admin/",        // wordpress scan
  "/.env", "/.git/config", "/admin",    // sensitive-file / admin probing
  "/phpmyadmin/", "/actuator/health",   // tech probing
];

export default function () {
  // Mostly probing 404s (drives http-probing), some known attack payloads.
  const p = Math.random() < 0.4
    ? PATHS[Math.floor(Math.random() * PATHS.length)]
    : "/nonexistent-" + Math.random().toString(36).slice(2, 10);
  const res = http.get(`${TARGET}${p}`, { headers: { 'User-Agent': 'sqlmap/1.7' } });
  check(res, { 'handled': (r) => r.status > 0 });
}
