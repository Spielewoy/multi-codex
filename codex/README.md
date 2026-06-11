# codex — OpenAI Codex CLI

**Strategy:** `env` — sets `CODEX_HOME={profileDir}` before launch.

Codex stores everything (auth, config, sessions) under `~/.codex/` by default, but always checks `CODEX_HOME` first. Pointing it at a profile directory gives full account isolation with zero side effects.

## Install

```bash
npm i -g @openai/codex
```

## Quickstart

```bash
multi-cli new codex/work
multi-cli new codex/personal
codex-work       # logs into account A on first run
codex-personal   # logs into account B; both can run simultaneously
```

## Profile types

- **full** *(default)* — fresh `CODEX_HOME`, separate auth/config/sessions/skills.
- **shared** — symlinks `config.toml`, `skills/`, `agents/`, `prompts/`, `mcp-configs/`, `plugins/` from `~/.codex/`. Only `auth.json` and `sessions/` stay isolated.

## Continue a chat across accounts

Rate-limited on one account? Copy the conversation state to a profile logged into another, then resume the same chat.

```bash
multi-cli continue codex work personal   # copy sessions/history (never auth)
codex-personal
codex resume <session-id>                 # codex ≥ 0.30
```

Run `codex resume` with no argument to pick from past sessions interactively — no id lookup needed. The id is otherwise the UUID in the rollout filename under `sessions/YYYY/MM/DD/`.

`base` works as either profile name and means `~/.codex`. Default merge keeps newer destination files; `--no-merge` overwrites, `--dry-run` previews.

## Verified

Smoke-tested live against `codex-cli 0.130.0` on Windows.
