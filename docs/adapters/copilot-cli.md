# copilot-cli: GitHub Copilot CLI

**Account boundary:** `processSecret`: a per-process `COPILOT_GITHUB_TOKEN` injected at launch; inherited `GH_TOKEN`/`GITHUB_TOKEN` are cleared so the process cannot fall back to the wrong account.

The adapter points `COPILOT_HOME` at the native shared root, so configuration and session state are shared normal state while the token stays inside the child process.

## Install

[docs.github.com: install Copilot CLI](https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli): binary: `copilot` on PATH.

## Quickstart

```bash
multi-cli new copilot-cli/work
multi-cli auth set copilot-cli/work      # stores COPILOT_GITHUB_TOKEN in the OS credential store
multi-cli launch copilot-cli/work
multi-cli new copilot-cli/personal
multi-cli auth set copilot-cli/personal
multi-cli launch copilot-cli/personal
```

`multi-cli auth status copilot-cli/work` reports presence only; `multi-cli auth clear copilot-cli/work` removes the stored token.

## Account boundary

- Profile-local credentials: none on disk: the token lives in the multi-cli credential store and is passed as `COPILOT_GITHUB_TOKEN` to the child process only.
- Credential precedence: `COPILOT_GITHUB_TOKEN` > `GH_TOKEN` > `GITHUB_TOKEN` > copilot-cli keychain > `gh auth token`. The inherited lower-priority variables are cleared at launch.
- Launch env: `COPILOT_HOME={sharedStateRoot}`; clears `GH_TOKEN`, `GITHUB_TOKEN`.
- Logout scope: process.

## Shared normal state

Shared root: `%USERPROFILE%\.copilot` (Windows), `~/.copilot` (macOS/Linux).

- Config: `settings.json`, `lsp-config.json`, `mcp-config.json`, `permissions-config.json`, `copilot-instructions.md`, `agents/`, `instructions/`, `skills/`, `hooks/`, `extensions/`, `installed-plugins/`, `plugin-data/`, `ide/`, `logs/`.
- Sessions: `session-state/`, `command-history-state/`, `session-store.db`.

## Known limitations

- `~/.copilot` is mixed: `config.json`, `mcp-oauth-config/`, and `mcp-secrets/` are declared unsafe (credential-bearing) and are never linked. Only the declared paths above are shared.
- `session-store.db` is shared normal state; concurrent profiles share it.

## Support

| Windows | macOS | Linux |
|---|---|---|
| supported (process token via `multi-cli auth set`; `GH_TOKEN`/`GITHUB_TOKEN` cleared) | supported | supported |
