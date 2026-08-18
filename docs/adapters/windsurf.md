# windsurf: Devin Desktop (Windsurf)

**Account boundary:** `osUserCredentialStore`: Devin account or manual API-key login has no documented per-profile namespace, so shared profiles use an owned OS user. `--isolated` provides a whole-root alternative.

Windsurf is now Devin Desktop. The adapter detects both current and legacy binaries: `devin-desktop`, `surf`, `windsurf`.

## Install

[docs.devin.ai/desktop/getting-started](https://docs.devin.ai/desktop/getting-started)

## Quickstart

Windows account profiles use an owned OS user:

```bash
multi-cli new windsurf/work
multi-cli launch windsurf/work
```

macOS and Linux can use an owned OS user with `sudo`, or a whole-root profile:

```bash
multi-cli new windsurf/work --isolated
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
- Legacy Windsurf paths may still be read by current binaries, so whole-root or OS-user isolation must include them.

## Support

| Windows | macOS | Linux |
|---|---|---|
| supported (owned OS user; elevated terminal) | supported (owned OS user with `sudo`, or `--isolated`) | supported (owned OS user with `sudo` and `acl`, or `--isolated`) |
