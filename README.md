# local_llm

Self-hosted Qwen3-Coder behind a LiteLLM proxy, designed for use with opencode (or any OpenAI-compatible client).

## Stack

- **vLLM** serves `Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8` on the internal Docker network only (no host port).
- **LiteLLM** is the only externally-exposed service (`:4000`). It handles per-user virtual API keys, request logging, and budgets, persisting them to Postgres.
- **Postgres 16** stores LiteLLM's keys, spend, and model config.

```
opencode --(sk-user-…)--> :4000 LiteLLM --(VLLM_UPSTREAM_KEY)--> vllm:8000
                              └──> postgres:5432
```

## First-time setup

1. Copy the env template and fill in your HF token. The other secrets are pre-generated:
   ```bash
   cp .env.example .env   # if starting fresh
   $EDITOR .env           # set HF_TOKEN, regenerate other keys if desired
   ```
   To regenerate secrets:
   ```bash
   echo "VLLM_UPSTREAM_KEY=sk-vllm-$(openssl rand -hex 24)"
   echo "LITELLM_MASTER_KEY=sk-master-$(openssl rand -hex 24)"
   echo "LITELLM_SALT_KEY=$(openssl rand -hex 32)"
   echo "PG_PASSWORD=$(openssl rand -hex 16)"
   ```
2. Bring it up:
   ```bash
   docker compose up -d
   docker compose logs -f vllm
   ```
   First boot pulls ~30 GB of FP8 weights into `./hf-cache/`. The vLLM healthcheck has a 120 s start period; LiteLLM waits for it before starting.

3. Sanity check once healthy:
   ```bash
   curl http://localhost:4000/health -H "Authorization: Bearer $LITELLM_MASTER_KEY"
   ```

## Minting a key for opencode

Don't hand out the master key. Generate a scoped virtual key:

```bash
curl -X POST http://localhost:4000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"models":["qwen3-coder"],"key_alias":"opencode","max_budget":100}'
```

Configure opencode by creating `~/.config/opencode/config.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "grace": {
      "name": "Grace Hopper",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://<host>:4000/v1",
        "apiKey": "sk-..."
      },
      "models": {
        "qwen3-coder": {
          "id": "qwen3-coder",
          "name": "Qwen3 Coder",
          "tool_call": true,
          "temperature": true,
          "limit": {
            "context": 65536,
            "output": 16384
          }
        }
      }
    }
  },
  "model": "grace/qwen3-coder"
}
```

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Service definitions, GPU reservation, healthchecks |
| `litellm.yaml` | LiteLLM model routing — points `qwen3-coder` at the internal vLLM |
| `.env` | Secrets (gitignored) |
| `.env.example` | Template for `.env` |
| `hf-cache/` | Hugging Face model cache (gitignored) |
| `pgdata/` | Postgres data volume (gitignored) |

## vLLM config notes

- `--max-model-len 65536` — 64k context. Drop this if you need more concurrent requests.
- `--kv-cache-dtype fp8` — requires SM 89+ (Grace Hopper is SM 90, fine).
- `--enable-prefix-caching` — big win for opencode-style repeated prompts.
- `--tool-call-parser hermes` — works for Qwen3-Coder's tool-call format. If tool calls misbehave, try the `qwen` parser variant.

## Operations

```bash
# tail vLLM
docker compose logs -f vllm

# restart just the proxy after editing litellm.yaml
docker compose restart litellm

# wipe everything (including DB and HF cache)
docker compose down -v
rm -rf pgdata/ hf-cache/

# update vLLM — bump the pinned tag in docker-compose.yml, then:
docker compose pull vllm && docker compose up -d vllm
```
