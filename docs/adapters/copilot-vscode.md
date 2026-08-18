# copilot-vscode: GitHub Copilot in VS Code

**Account boundary:** `osUserCredentialStore`: Copilot identity lives in the VS Code GitHub authentication and extension credential store, so profiles are isolated by an owned OS user.

This adapter models the real host: VS Code (`code`) plus the official Copilot extension: not a standalone IDE. Other IDE hosts are not claimed by this adapter.

## Install

[docs.github.com: install the Copilot extension](https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-extension)

Binary discovery: `code.cmd` / `code` (Windows), `code` (macOS/Linux).

## Quickstart

```bash
multi-cli new copilot-vscode/work
multi-cli launch copilot-vscode/work    # runs under a profile-owned OS user
multi-cli new copilot-vscode/personal
multi-cli launch copilot-vscode/personal
```

On Windows, the first shared-profile launch provisions an owned OS user. macOS and Linux remain unsupported until real owned-user GUI and credential-store sessions are implemented and verified.

## Account boundary

- Profile-local credentials: VS Code GitHub authentication plus the Copilot extension credential store, scoped to the profile's owned OS user.
- Logout scope: OS user.
- Concurrency: single writer per host profile (`singletonScope: hostProfile`).

## Shared normal state

None claimed. `User/globalStorage/` and `User/workspaceStorage/` under the VS Code data root (`%APPDATA%\Code` on Windows, `~/Library/Application Support/Code` on macOS, `~/.config/Code` on Linux) are declared unsafe and are never shared.

## Known limitations

- Editor and Copilot ordinary state are intentionally not split; nothing is shared.
- OS-user profiles require administrator access on Windows. macOS and Linux are not advertised as supported.

## Support

| Windows | macOS | Linux |
|---|---|---|
| supported (owned OS user; elevated terminal) | unsupported (owned-user GUI/Keychain session not proven) | unsupported (owned-user GUI/Secret Service session not implemented) |
