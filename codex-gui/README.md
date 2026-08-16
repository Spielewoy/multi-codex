# codex-gui: Codex desktop app

Codex GUI is the OpenAI desktop application. It is a GUI, not an IDE.

On Windows, each profile runs the Microsoft Store package as a local Windows user owned by multi-cli. This separates the Windows profile, Credential Manager, `%APPDATA%`, `%LOCALAPPDATA%`, `.codex`, and AppX local state.

Windows support is experimental until the real secondary-user AppX test passes for the applicable Windows and Codex package versions.

## Install

```powershell
winget install --id 9PLM9XGG6VKS -s msstore
```

## Create and launch a profile

Create the profile once from an elevated PowerShell terminal:

```powershell
multi-cli new codex-gui/work
```

The `new` command performs the admin preflight before writing profile data, then creates the owned local user and stores its generated password in Windows Credential Manager.

Launches do not require elevation after setup:

```powershell
multi-cli launch codex-gui/work
```

The launcher resolves the installed package family, registers it for the owned user, activates its adapter-declared AUMID, and verifies the returned process owner and interactive session. A Start Menu shortcut is created only after this verification succeeds. The shortcut calls the same verified launcher.

## Isolation boundary

Local state and cloud data are different boundaries:

- The owned Windows user separates local credentials, files, settings, and AppX state.
- Signing two profiles into the same OpenAI account can show the same server-side conversations and projects. Use separate OpenAI accounts for separate cloud history.
- Service-controlled system prompts cannot be reset or customized by multi-cli.
- `--isolated` is refused because folder redirection does not isolate Windows Credential Manager.

Nothing from the operator's normal Codex profile is copied, redirected, or modified. The launcher does not execute a copied Store payload and does not retry activation as the operator.

## Failure behavior

A launch succeeds only when all of these checks pass:

```text
AppX registration exists for the owned user
AND activation returns a live process
AND the process belongs to the owned user
AND the process uses the initiating interactive session
```

Failures use the stable code `unsupported_appx_secondary_user` and report the package, owned user, phase, and Windows error. A failed launch does not create an isolated shortcut.

## Real Windows test

The opt-in test is intentionally excluded from normal CI because it creates a local user and launches the installed GUI:

```powershell
$env:MULTICLI_REAL_APPX_E2E = '1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\e2e\windows\Invoke-CodexGuiAppxE2E.ps1
```

The test records the Windows build, package version, AUMID, process owner SID, and session. It never stops an existing Codex process.

## Platform support

| Windows | macOS | Linux |
|---|---|---|
| experimental (secondary-user AppX launch with owner and session checks; real Windows E2E required) | unsupported (owned-user GUI and Keychain session not proven) | unsupported (no Codex desktop app) |
