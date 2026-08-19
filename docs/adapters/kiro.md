# kiro: Kiro IDE

**Account boundary:** `osUserCredentialStore`: Kiro's browser/IAM sign-in has no per-profile credential namespace, so profiles use an owned OS user.

Kiro is an agentic IDE. No IDE-internal credential file or keychain namespace is documented as profile-safe, so multi-cli does not claim one.

## Install

[kiro.dev/docs/getting-started/installation](https://kiro.dev/docs/getting-started/installation/): binary: `kiro` on PATH.

## Quickstart

Profiles use an owned OS user:

```bash
multi-cli new kiro/work
multi-cli launch kiro/work
```

## Account boundary

- Profile-local credentials: the IDE browser/IAM sign-in, scoped to the profile's owned OS user.
- Logout scope: OS user.
- Concurrency: single writer per OS user (`singletonScope: osUser`).

## Shared normal state

None claimed yet. The native root (`%USERPROFILE%\.kiro` on Windows, `~/.kiro` on macOS/Linux) is recorded, but no settings, agents, prompts, steering, or session paths are shared until live tracing proves them credential-free.

## Known limitations

- Safe shared-state paths are intentionally empty until vendor tracing proves they are credential-free.
- Owned OS-user profiles require administrator access on Windows and `sudo` on macOS/Linux.
- `--isolated` is rejected because folder redirection cannot isolate the fixed OS credential store.

## Support

| Windows | macOS | Linux |
|---|---|---|
| supported (owned OS user; elevated terminal) | supported (owned OS user with `sudo`) | supported (owned OS user with `sudo` and `acl`) |
