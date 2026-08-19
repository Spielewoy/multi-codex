# windsurf: Devin Desktop (Windsurf)

**Account boundary:** `osUserCredentialStore`: Devin account or manual API-key login has no documented per-profile namespace, so profiles use an owned OS user.

Windsurf is now Devin Desktop. The adapter detects both current and legacy binaries: `devin-desktop`, `surf`, `windsurf`.

## Install

[docs.devin.ai/desktop/getting-started](https://docs.devin.ai/desktop/getting-started)

## Quickstart

Profiles use an owned OS user:

```bash
multi-cli new windsurf/work
multi-cli launch windsurf/work
```

## Account boundary

- Profile-local credentials: the Devin account or manual API-key login, scoped to the profile's owned OS user.
- Logout scope: OS user.
- Concurrency: single writer; singleton behavior is undocumented (`singletonScope: unknown`).

## Shared normal state

None claimed. Persistent state uses `~/.codeium/windsurf` on Windows, macOS, and Linux (with `~` resolved to the profile-owned user's home).

## Known limitations

- Nothing is shared because current and legacy data roots can contain account state.
- Legacy Windsurf paths may still be read by current binaries, so OS-user isolation must include them.
- `--isolated` is rejected because folder redirection cannot isolate the fixed OS credential store.

## Support

| Windows | macOS | Linux |
|---|---|---|
| supported (owned OS user; elevated terminal) | supported (owned OS user with `sudo`) | supported (owned OS user with `sudo` and `acl`) |
