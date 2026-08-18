# codex-gui: Codex Desktop App

Codex GUI is the desktop application, not an IDE. On Windows, an owned OS user separates Credential Manager, AppX data, and the user's `.codex` state.

OpenAI ships the Codex app for Windows and macOS. The app and native Codex CLI share the user's `.codex` tree; running the app as a profile-owned user gives each profile a separate credential and data namespace.

## Install

Windows:

```powershell
winget install --id 9PLM9XGG6VKS -s msstore
```

macOS: download the Codex app from [OpenAI's Codex app page](https://openai.com/index/introducing-the-codex-app/).

## Quickstart

```powershell
multi-cli new codex-gui/work
multi-cli launch codex-gui/work
```

The first launch requires an elevated terminal so multi-cli can provision the owned Windows user. Later launches use that stored identity. The launcher registers the Store package for that user and activates its AppX application instead of copying or directly running the protected package executable.

## Account boundary

- Mechanism: `osUserCredentialStore`.
- Profile-local state: the owned user's `.codex` tree and credential namespace.
- Logout scope: owned OS user.
- Concurrency: one app instance per owned OS user.

## Shared normal state

Nothing is shared because the app's authentication, configuration, and sessions use the same `.codex` tree. Use `multi-cli continue codex ...` for portable CLI sessions when needed.

This boundary is local. Profiles signed into the same OpenAI account can still show the same server-side conversations and projects. Use separate OpenAI accounts when cloud history must also be separate. multi-cli cannot reset or customize service-controlled system prompts.

## Known limitations

- Linux has no native Codex desktop app.
- `--isolated` is rejected because folder redirection does not isolate Windows Credential Manager.
- Launch fails unless the activated GUI belongs to the owned user, remains visible, and uses the initiating Windows session.

## Support

| Windows | macOS | Linux |
|---|---|---|
| supported (Store app + owned OS user; elevated terminal) | unsupported (owned-user GUI/Keychain session not proven) | unsupported (no Codex desktop app) |
