# cursor: Cursor Desktop

**Account boundary:** `inseparable`: desktop credentials, chat state, SQLite global storage, and singleton behavior have no proven narrow split.

Cursor accepts VS Code-style user-data flags, but per `adapter.json` those flags do not prove separate desktop auth with shared conversations. The account-overlay contract is therefore not claimed.

## Install

[cursor.com/download](https://cursor.com/download)

Binary discovery: `%LOCALAPPDATA%\Programs\cursor\Cursor.exe` (Windows), `/Applications/Cursor.app` (macOS), `/usr/bin/cursor` or `/opt/Cursor/cursor` (Linux).

## Quickstart

Use a whole-root profile for Cursor Desktop:

```bash
multi-cli new cursor/work --isolated
multi-cli launch cursor/work
```

For a process-token boundary, use the Cursor CLI adapter (`cursor-cli`).

## Account boundary

- Mechanism: `inseparable`: credentials, chat databases, and global storage are not proven separable.
- Logout scope: user.
- Concurrency: single instance per OS user (`singletonScope: user`).

## Shared normal state

None claimed. `adapter.json` declares no shared, session, or file paths under the native root (`%USERPROFILE%\.cursor` on Windows, `~/.cursor` on macOS/Linux).

## Known limitations

- Chat history lives in SQLite keyed to workspace state and cannot be portably shared or copied between profiles.
- A narrower boundary requires proof that auth, chat databases, and single-instance behavior are separable; until then nothing is shared.

## Support

| Windows | macOS | Linux |
|---|---|---|
| supported (`--isolated`) | supported (`--isolated`) | supported (`--isolated`) |
