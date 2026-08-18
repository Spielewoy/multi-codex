# zed: Zed

**Account boundary:** `osUserCredentialStore`: each profile runs under a multi-cli-owned OS user, separating Zed's credential store, process namespace, and data root.

Zed is a singleton per release channel and OS user. An owned OS user gives each profile a separate process and credential namespace, including same-channel concurrent profiles.

## Install

[zed.dev/docs/installation](https://zed.dev/docs/installation)

Binary discovery: `zed` or `zeditor` (Linux), `zed.exe` (Windows), `/usr/local/bin/zed` (macOS).

## Quickstart

```bash
multi-cli new zed/work
multi-cli launch zed/work
multi-cli new zed/personal
multi-cli launch zed/personal
```

The first launch requires an elevated terminal on Windows so multi-cli can provision the owned OS user. macOS and Linux remain unsupported until a real owned-user desktop credential session is implemented and verified.

## Account boundary

- Profile-local credentials: Zed's credential store under the profile-owned OS user.
- Logout scope: OS user.
- Singleton scope: release channel and OS user (`releaseChannelAndOsUser`).

## Shared normal state

None claimed yet. Native roots: `%LOCALAPPDATA%\Zed` (Windows), `~/Library/Application Support/Zed` (macOS), `~/.local/share/zed` (Linux).

The `db/` directory (SQLite) is declared unsafe and is never shared until dual-process database concurrency is proven.

## Known limitations

- Same-channel singleton behavior requires separate OS users for concurrent Windows windows; macOS/Linux owned-user GUI sessions are not yet supported.
- `--isolated` is rejected because folder redirection cannot isolate the fixed OS credential store.
- The `db/` tree is never shared across profiles.

## Support

| Windows | macOS | Linux |
|---|---|---|
| supported (owned OS user; elevated terminal) | unsupported (owned-user GUI/Keychain session not proven) | unsupported (owned-user GUI/Secret Service session not implemented) |
