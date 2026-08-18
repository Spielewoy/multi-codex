# antigravity: Google Antigravity IDE

**Account boundary:** `osUserCredentialStore`: Antigravity authenticates through fixed OS credential entries, so each profile runs under a multi-cli-owned OS user.

Antigravity IDE 2.x stores its account under a fixed keychain identity (`gemini:antigravity` on Windows, `gemini/antigravity` on macOS, `service=gemini username=antigravity` on Linux). Two profiles under the same OS user overwrite each other's login; a dedicated OS user per profile is the only declared boundary.

## Install

[antigravity.google.com](https://antigravity.google.com/)

Binary discovery: `%LOCALAPPDATA%\Programs\Antigravity\Antigravity.exe` (Windows), `/Applications/Antigravity.app` (macOS), `/usr/bin/antigravity` or `/opt/Antigravity/antigravity` (Linux).

## Quickstart

```bash
multi-cli new antigravity/work
multi-cli launch antigravity/work       # first launch provisions a profile-owned OS user
multi-cli new antigravity/personal
multi-cli launch antigravity/personal
```

The first launch requires an elevated terminal on Windows so multi-cli can provision the owned OS user. macOS and Linux remain unsupported until a real owned-user login/desktop credential session is implemented and verified.

## Account boundary

- Profile-local credentials: the fixed OS credential entry, scoped to the profile's owned OS user.
- Logout scope: OS user.
- Concurrency: single writer per OS user (`singletonScope: osUser`).

## Shared normal state

None claimed yet. Native roots: `%APPDATA%\Antigravity IDE` (Windows), `~/Library/Application Support/Antigravity IDE` (macOS), `~/.config/Antigravity IDE` (Linux).

`User/globalStorage/storage.json` and `User/globalStorage/state.vscdb` are declared unsafe: account data and IDE state are not proven separable inside them, so they are never linked or shared.

## Known limitations

- The fixed keychain identity makes same-OS-user dual accounts impossible. Windows owned-user isolation is supported; macOS and Linux remain unsupported.
- `--isolated` is rejected because folder redirection cannot isolate the fixed OS credential store.
- No normal state is shared until database tracing proves which paths are credential-free.
- Authenticated GUI testing requires two test accounts; the runtime and cleanup paths are covered by platform tests.

## Support

| Windows | macOS | Linux |
|---|---|---|
| supported (owned OS user; elevated terminal) | unsupported (owned-user GUI/Keychain session not proven) | unsupported (owned-user GUI/Secret Service session not implemented) |
