# codex: OpenAI Codex CLI

**Account boundary:** `fileOverlay`: `auth.json` is profile-local; configuration and sessions are shared normal state.

Codex honors `CODEX_HOME`. The adapter points it at a per-profile runtime view where only `auth.json` belongs to the profile and every declared ordinary path links back to the native shared root.

## Install

```bash
npm i -g @openai/codex
```

Binary discovery: `%APPDATA%\npm\codex.cmd` (Windows), `/usr/local/bin/codex` (macOS), `$HOME/.npm-global/bin/codex` (Linux), then `codex` on PATH.

## Quickstart

```bash
multi-cli new codex/work
multi-cli launch codex/work        # sign in on first run; auth.json stays profile-local
multi-cli new codex/personal
multi-cli launch codex/personal
```

Conversations are shared normal state, so `multi-cli continue` is not needed between schema-v2 profiles (it remains available for legacy profiles).

## Account boundary

- Profile-local credentials: `auth.json` (sole declared credential). Requires Codex file credential storage.
- Launch env: `CODEX_HOME={runtimeRoot}`.
- Logout scope: profile.

## Shared normal state

Shared root: `%USERPROFILE%\.codex` (Windows), `~/.codex` (macOS/Linux).

- Config: `config.toml`, `hooks.json`, `skills/`, `agents/`, `prompts/`, `mcp-configs/`, `plugins/`.
- Sessions: `sessions/`, `history.jsonl`, `archived_sessions/`, `session_index.jsonl`.

## Known limitations

- Requires file-based credential storage (`auth.json`); OS-keychain credential modes are outside this account boundary.
- Concurrent profiles write to the shared session store; keep simultaneous writers in mind.

## Support

| Windows | macOS | Linux |
|---|---|---|
| supported (file overlay; file credential store mode) | supported | supported |
