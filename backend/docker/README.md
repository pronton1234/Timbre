# Self-hosted Cobalt v11 deploy notes (VM)

Why this exists: the public Cobalt v7 API and the Piped public-mirror ecosystem
are both dead as of April 2026 (see plan Phase 9). We run our own Cobalt v11 on
the same Oracle ARM VM as the Node backend so the extractor fallback chain has
a second live option that is genuinely independent of yt-dlp.

Loopback topology:
- Cobalt container binds to `127.0.0.1:9000`
- Node backend reaches it via `COBALT_BASE_URL=http://127.0.0.1:9000`
- AVPlayer (phone) reaches tunnel URLs via `https://free-spotify.duckdns.org/cobalt/`
  (nginx reverse-proxies `/cobalt/` → `127.0.0.1:9000/`)

## 1. Install Docker (one-time, on the ARM VM)

```bash
ssh ubuntu@<vm-ip>
# Docker's official repo (arm64)
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker ubuntu
# log out / log back in so the group takes effect
exit
ssh ubuntu@<vm-ip>
docker --version       # expect 24+
docker compose version # expect v2 plugin
```

## 2. Convert YouTube cookies (Netscape → Cobalt JSON)

Cobalt v11 reads `cookies.json` in its own shape — a single JSON object keyed
by service. Our existing `yt-cookies.txt` is Netscape format (for yt-dlp).

On the VM:
```bash
cd /home/ubuntu/spotify-free/backend
mkdir -p docker/cookies
node -e '
const fs = require("fs");
const lines = fs.readFileSync("yt-cookies.txt", "utf8").split("\n");
const kv = [];
for (const line of lines) {
  if (!line || line.startsWith("#")) continue;
  const parts = line.split("\t");
  if (parts.length < 7) continue;
  const [_d, _f, _p, _s, _e, name, value] = parts;
  if (!name || !value) continue;
  // Cobalt wants the raw "name=value" cookie string form.
  kv.push(`${name}=${value}`);
}
const out = { youtube: [kv.join("; ")] };
fs.writeFileSync("docker/cookies/cookies.json", JSON.stringify(out, null, 2));
console.log("wrote", kv.length, "cookies");
'
chmod 600 docker/cookies/cookies.json
```

Refresh cookies whenever yt-dlp starts 403-ing (same cadence as today) — rerun
the conversion above.

## 3. Start the container

```bash
cd /home/ubuntu/spotify-free/backend/docker
docker compose -f docker-compose.cobalt.yml up -d
docker compose -f docker-compose.cobalt.yml logs --tail=100 -f
```

Smoke test from the VM shell:
```bash
curl -sS http://127.0.0.1:9000/ | head -c 200
# expect JSON with "cobalt" and version
```

End-to-end extraction test (the video yt-dlp was gated on):
```bash
curl -sS -X POST http://127.0.0.1:9000/ \
  -H 'content-type: application/json' \
  -d '{"url":"https://youtu.be/c9qBHNKfiJw","downloadMode":"audio","audioFormat":"best"}' | jq .
# expect {"status":"tunnel","url":"https://free-spotify.duckdns.org/cobalt/api/stream/..."}
```

## 4. nginx subpath reverse proxy

Edit `/etc/nginx/sites-available/spotify-free` (or wherever the existing
free-spotify.duckdns.org server block lives) and add **inside the `server {}`
that already terminates TLS for `free-spotify.duckdns.org`**:

```nginx
location /cobalt/ {
    proxy_pass http://127.0.0.1:9000/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Tunneled audio can be several minutes long; disable buffering so
    # AVPlayer gets a true streaming pipe.
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_read_timeout 600s;
    proxy_send_timeout 600s;

    # Preserve Range requests — AVPlayer relies on byte-range seeking.
    proxy_set_header Range $http_range;
    proxy_set_header If-Range $http_if_range;
    proxy_pass_header Content-Range;
    proxy_pass_header Accept-Ranges;
}
```

Reload:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

Smoke test over HTTPS:
```bash
curl -sS https://free-spotify.duckdns.org/cobalt/ | head -c 200
# same JSON banner as the 127.0.0.1:9000 test
```

## 5. Wire the Node backend

Add to `/etc/systemd/system/spotify-free-backend.service.d/override.conf`
(create the drop-in if it doesn't exist):
```
[Service]
Environment=COBALT_BASE_URL=http://127.0.0.1:9000
```

Then:
```bash
sudo systemctl daemon-reload
sudo systemctl restart spotify-free-backend
sudo journalctl -u spotify-free-backend -f
```

## 6. Verify the fallback chain end-to-end

Force-open the ytdlp circuit to prove Cobalt can carry the request alone:
```bash
# Trip ytdlp breaker: 3 consecutive calls to a guaranteed-failing videoId
for i in 1 2 3; do
  curl -sS 'https://free-spotify.duckdns.org/stream?videoId=xxxxxxxxxxx' -o /dev/null -w '%{http_code}\n'
done
# Now request the previously-gated track
curl -sS 'https://free-spotify.duckdns.org/resolve?title=GATTI&artist=JACKBOYS&durationMs=222000' | jq .
# expect .streamUrl to be a free-spotify.duckdns.org/cobalt/... URL and HTTP 200
```

## Known gotchas

- **ARM64 image availability.** `ghcr.io/imputnet/cobalt:11` is a multi-arch
  manifest; `docker pull` picks arm64 automatically on A1.Flex. If
  `exec format error` shows up, check `docker image inspect` for `Architecture`.
- **RATELIMIT_MAX too low.** Cobalt rate-limits per-IP. Our Node backend is a
  single IP (127.0.0.1), so one user hammering skip can easily exceed the
  default 20/min. We ship `120/min` — raise further if the regression corpus
  starts seeing `rate_limit` errors.
- **nginx buffering.** If `proxy_buffering` is not disabled for `/cobalt/`,
  AVPlayer sees TTFB spike to the full track length (nginx tries to buffer
  the whole audio before forwarding). The config above disables it.
- **Cookies format.** Do NOT symlink or copy `yt-cookies.txt` to
  `cookies.json` — the format is completely different and Cobalt will ignore
  Netscape files silently, leaving you with an uncookied session that will
  bot-gate the same way yt-dlp does.
