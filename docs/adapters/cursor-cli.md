# cursor-cli: Cursor CLI

**Account boundary:** `processSecret`: a per-process `CURSOR_API_KEY` injected at launch is the only credential; `cli-config.json` is shared normal state.

Cursor CLI installs the `agent` binary. The adapter points `CURSOR_CONFIG_DIR` at the native shared root and injects the profile's key into the child process only: nothing credential-bearing touches disk.

## Install

[cursor.com/docs/cli](https://cursor.com/docs/cli): binary: `agent` on PATH (all platforms).

## Quickstart

```bash
multi-cli new cursor-cli/work
multi-cli auth set cursor-cli/work      # stores CURSOR_API_KEY in the OS credential store
multi-cli launch cursor-cli/work
multi-cli new cursor-cli/personal
multi-cli auth set cursor-cli/personal
multi-cli launch cursor-cli/personal
```

`multi-cli auth status cursor-cli/work` reports presence only; `multi-cli auth clear cursor-cli/work` removes the stored key.

## Account boundary

- Profile-local credentials: none on disk: the key lives in the multi-cli credential store and is passed as `CURSOR_API_KEY` to the child process only.
- Credential precedence: `CURSOR_API_KEY` (sole declared entry).
- Launch env: `CURSOR_CONFIG_DIR={sharedStateRoot}`.
- Logout scope: process: nothing persists after exit.

## Shared normal state

Shared root: `%USERPROFILE%\.cursor` (Windows), `~/.cursor` (macOS/Linux). Shared: `cli-config.json`. No session paths are declared.

## Known limitations

- `CURSOR_API_KEY` is the sole declared credential; store it per profile with `multi-cli auth set`.
- Browser-login desktop state is out of scope for this adapter; see `cursor` (`--isolated` whole-root) for the IDE.

## Support

| Windows | macOS | Linux |
|---|---|---|
| supported (process token via `multi-cli auth set`) | supported | supported |
