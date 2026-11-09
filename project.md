# Bifrost gateway on aipc

Status: **running, LAN-reachable at http://192.168.50.66:8080** (2026-11-08). Goal: hand out API
keys so other people on the home network can use the local model. Own apps not migrated (Tate: not yet).

## Goal

Put [Bifrost](https://docs.getbifrost.ai) (Maxim's open-source LLM gateway, OpenAI-compatible
API) in front of the models on this box. Clients would talk to one URL, and Bifrost would route
to the right backend with logging, fallbacks and per-client keys.

> To confirm with Tate: what's the main win? Options below; pick one or more.
> - One endpoint for every client instead of each one hardcoding `:30000`
> - Request logs and metrics for the local model (tokens, latency, errors)
> - Fallback to a cloud model when the local server is down or stopped for benchmarks
> - Per-client virtual keys and budgets (e.g. the Signal bridge vs. omp)
> - MCP tool gateway

## What's on the box today

| Thing | Where | Talks to |
|---|---|---|
| SGLang, daily model Qwen3.8-27B TP=2 on both GPUs (36.9k ctx; was Gemma 4 12B until 2026-11-06) | `127.0.0.1:30000`, user service `sglang-daily` | — |
| Ollama | `127.0.0.1:11434` | — |
| omp coding agent | `~/.omp/agent/models.yml` | `:30000` directly |
| Signal bridge | `~/signal-bridge/config.toml`, `model.py` | `:30000` directly |
| Open WebUI (docker) | `0.0.0.0:3000` | (check) |
| SearXNG (docker) | `127.0.0.1:8888` | — |
| Bench harness | `~/bench` | starts its own SGLang on `:30000`; **should bypass the gateway** |

Port 8080 (Bifrost's default) is free. Docker 29.7.1 is installed.

Note while surveying: Open WebUI listens on **0.0.0.0:3000**, so it's reachable from the LAN.
That may be intentional; worth deciding before adding another service.

## Proposed shape

```
omp ─────────┐
signal-bridge ┼──> Bifrost 127.0.0.1:8080 ──> SGLang :30000   (local, default)
Open WebUI ──┘          │                └──> Ollama :11434   (optional)
                        └──> cloud provider            (optional fallback)
```

- Run in Docker, pinned to a specific image tag (not `latest`), with `-v ./data:/app/data` for
  persistence. Bind to `127.0.0.1` only.
- Add SGLang as a custom OpenAI-compatible provider. **Unverified: the exact config keys for a
  custom base URL.** Check the docs before writing config.
- Move clients over one at a time, keeping the old direct URL in a comment so rollback is one edit.

## Phases

1. **Decide scope.** Answer the goal question above, and decide whether cloud fallback is wanted
   (it needs an API key, and means requests can leave the box).
2. **Vet it.** Same bar as the models: pick a release, check the image digest and the repo,
   read what it phones home (telemetry), and confirm it runs fully offline against local backends.
3. **Stand it up.** Docker run on `127.0.0.1:8080`, local SGLang provider only. Smoke-test with
   `curl /v1/chat/completions` and a streaming request.
4. **Prove it doesn't break the model.** Check streaming, tool calls, and that `max_tokens`,
   `top_k` and `chat_template_kwargs.enable_thinking` pass through. Gemma's sampling and the
   thinking-off setting live in omp's `extraBody`; a gateway that drops unknown fields would
   silently undo the benchmarked config.
5. **Migrate clients.** omp first (rerun one `~/bench` omp task through the gateway and compare),
   then the Signal bridge, then Open WebUI.
6. **Run it as a service.** systemd user unit or Docker restart policy, tracked in
   `local-model-config` via `sync.sh`.

## Risks and traps to keep in mind

- **Context limits:** omp's `contextWindow: 117444` and the compaction settings assume the
  server's real KV pool. The gateway must not add tokens or cap lengths.
- **Benchmarks:** `~/bench` restarts SGLang on `:30000`. During a run, gateway traffic would hit a
  restarting server. Either stop clients during benchmarks or let Bifrost fail over.
- **Fallback leaks:** if a cloud fallback is configured, a local outage silently sends prompts
  (Signal messages included) to the cloud. Make that opt-in per client.
- **Webguard:** decide whether Bifrost's own outbound traffic should go through the web filter.

## Open questions

- [ ] Main goal(s) from the list above
- [ ] Cloud fallback: yes/no, which provider
- [ ] Include Ollama as a backend?
- [ ] Should Claude Code go through it too? (Only if it adds value; it has its own billing/logging.)
- [ ] Docker vs. the `npx` binary
- [ ] Repo: new private `bifrost-config`, or a folder inside `local-model-config`

## Log

- 2026-10-22: Project created. Surveyed ports and clients; confirmed Docker install path and
  default port 8080 from the Bifrost docs.
- 2026-11-08: Tate's goal: pass out API keys so others can use the LLM. Installed Bifrost
  v2.5.0 (image pinned by digest sha256:b5258c5f..., docker, `run.sh`, restart unless-stopped,
  host network, APP_HOST=127.0.0.1, read-only rootfs, cap-drop ALL, runs as uid 1000).
  Config: `config.json` (native `sgl` provider -> 127.0.0.1:30000, enforce_auth_on_inference,
  admin auth + setup token + encryption key from `.env` (0600), content logging OFF = metadata
  only, 90-day retention, sqlite stores in `data/` (0700)). Keys via `./bfkey new|list|off|on|rm`
  (default 20 req/min, 500k tok/day). Dashboard news feed turned off.
  Verified: no key -> 401 (inference + admin), chat, streaming, tool calls, rate limit -> 429,
  disabled key -> 403, `top_k` and `chat_template_kwargs.enable_thinking` pass through untouched,
  survives restart. Outbound: only GETs to getbifrost.ai/datasheet (public pricing list).
  Trap: sqlite paths must be absolute (`/app/data/...`); `./config.db` resolves outside the volume.
  Docs site is blocked by webguard; docs are in `src/bifrost/docs` (clone at the v2.5.0 tag).
  Clients (omp, bridge, Open WebUI) NOT migrated; they still hit :30000 directly.
- 2026-11-08: Tate chose **home LAN only** and **don't migrate own apps yet**. BIND=0.0.0.0 (so a
  DHCP change doesn't stop startup); verified a key works via 192.168.50.66 and the admin API is 401
  from the LAN. Only global IPv6 is ULA fc00:f853:... (KIND), so no internet path. TODO for Tate:
  DHCP reservation for 192.168.50.66 in the router.
