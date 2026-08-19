# grok-cli: Grok Build CLI

**Account boundary:** `processSecret`: a per-process `XAI_API_KEY`, valid only when no higher-precedence shared credential exists.

This adapter covers Grok Build's headless JSON mode, fullscreen TUI/dashboard, and ACP stdio surface.

## Install

[docs.x.ai/build/overview](https://docs.x.ai/build/overview): binary: `grok` on PATH (`grok version` prints the version).

## Quickstart

```bash
multi-cli new grok-cli/work
multi-cli auth set grok-cli/work      # stores XAI_API_KEY in the OS credential store
multi-cli launch grok-cli/work
multi-cli new grok-cli/personal
multi-cli auth set grok-cli/personal
multi-cli launch grok-cli/personal
```

`multi-cli auth status grok-cli/work` reports presence only; `multi-cli auth clear grok-cli/work` removes the stored key.

## Account boundary

- Profile-local credentials: none on disk: the key lives in the multi-cli credential store and is passed as `XAI_API_KEY` to the child process only.
- Credential precedence (highest first): `model.api_key` > `model.env_key` > active session > `XAI_API_KEY`.
- Launch env: `GROK_HOME={sharedStateRoot}`.
- Logout scope: process.

## Shared normal state

Shared root: `%USERPROFILE%\.grok` (Windows), `~/.grok` (macOS/Linux). Shared: `config.toml`, `sandbox.toml`, `crash/`. No session paths are declared.

## Known limitations

- `XAI_API_KEY` is the lowest-precedence credential. The shared `config.toml` must not set `model.api_key` or `model.env_key`, and no stored session may be active: otherwise every profile silently uses that stronger shared credential instead of its own key.
- Headless, ACP, and TUI surfaces all run through the same per-process token boundary.

## Support

| Windows | macOS | Linux |
|---|---|---|
| supported (process token via `multi-cli auth set`; shared config must not pin `model.api_key`) | supported | supported |
