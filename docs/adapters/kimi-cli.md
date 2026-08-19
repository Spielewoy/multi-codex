# kimi-cli: Kimi Code CLI

**Account boundary:** `processSecret`: a per-process `KIMI_MODEL_API_KEY` with explicit model/provider selection; documented config files are shared normal state.

The adapter points `KIMI_CODE_HOME` at the native shared root and injects the profile's key into the child process only. Profiles run as foreground processes.

## Install

[kimi.com/code/docs/en/kimi-code-cli](https://www.kimi.com/code/docs/en/kimi-code-cli/): binary: `kimi` on PATH.

## Quickstart

```bash
multi-cli new kimi-cli/work
multi-cli auth set kimi-cli/work      # stores KIMI_MODEL_API_KEY in the OS credential store
multi-cli launch kimi-cli/work        # foreground process
multi-cli new kimi-cli/personal
multi-cli auth set kimi-cli/personal
multi-cli launch kimi-cli/personal
```

`multi-cli auth status kimi-cli/work` reports presence only; `multi-cli auth clear kimi-cli/work` removes the stored key.

## Account boundary

- Profile-local credentials: none on disk: the key lives in the multi-cli credential store and is passed as `KIMI_MODEL_API_KEY` to the child process only.
- Credential precedence: `KIMI_MODEL_API_KEY` with explicit model/provider selection (sole declared entry).
- Launch env: `KIMI_CODE_HOME={sharedStateRoot}`.
- Logout scope: process.

## Shared normal state

Shared root: `%USERPROFILE%\.kimi-code` (Windows), `~/.kimi-code` (macOS/Linux). Shared: `config.toml`, `tui.toml`, `mcp.json`. No session paths are declared.

## Known limitations

- Foreground-only: Kimi background services use fixed names/ports (`singletonScope: backgroundService`), so two profiles must not run background services at once. multi-cli launches profiles as foreground processes only.
- Direct-provider mode requires explicit provider/model selection. This adapter does not provide isolated Kimi OAuth profiles; every launch requires a stored `KIMI_MODEL_API_KEY`.

## Support

| Windows | macOS | Linux |
|---|---|---|
| supported (process token via `multi-cli auth set`) | supported | supported |
