# Support matrix

`supported` means multi-cli provides working account isolation on that operating system through at least one mode. `experimental` means an implementation is available but still requires the stated real-system verification. `unsupported` means no isolation mode works on that OS, and the row says why.

| Adapter | Surface | Auth boundary | Shared normal state | Windows | macOS | Linux |
|---|---|---|---|---|---|---|
| `claude-cli` | Claude Code CLI | profile-local `.credentials.json` | `.claude` configuration and conversations | supported (file overlay) | supported for API-key profiles only; subscription OAuth is unsupported because its fixed Keychain identity is not isolated | supported (file overlay) |
| `codex` | Codex CLI | profile-local `auth.json`, file credential mode required | `.codex` configuration and conversations | supported (file overlay; file credential store mode) | supported | supported |
| `gemini-cli` | Gemini CLI | profile-local OAuth/account files | `.gemini` configuration and conversations | supported (file overlay) | supported | supported |
| `opencode` | OpenCode stored login | auth and sessions share one database | none | supported (`--isolated` whole-root required) | supported (`--isolated` whole-root required) | supported (`--isolated` whole-root required) |
| `commandcode` | Command Code | profile-local `.commandcode/auth.json` | `.commandcode` configuration and conversations | supported (file overlay; use `commandcode`, bare `cmd` collides with cmd.exe) | supported | supported |
| `cursor` | Cursor Desktop | whole-root profile; no narrow split claimed | none | supported (`--isolated` whole-root required) | supported (`--isolated` whole-root required) | supported (`--isolated` whole-root required) |
| `cursor-cli` | Cursor CLI | per-process `CURSOR_API_KEY` | `cli-config.json` | supported (process token via `multi-cli auth set`) | supported | supported |
| `antigravity` | Antigravity IDE 2.x | fixed OS credential, separate OS user required | none | supported (Windows OS-user isolation; elevated terminal) | unsupported — owned-user GUI/Keychain session is not proven | unsupported — owned-user GUI/Secret Service session is not implemented |
| `agy-cli` | Antigravity CLI | fixed OS credential, separate OS user required | settings/plugins/skills | supported (Windows OS-user isolation; elevated terminal) | unsupported — owned-user Keychain isolation is not proven | unsupported — owned-user Secret Service session is not implemented |
| `kiro` | Kiro IDE | separate OS user, or whole-root `--isolated` | none | supported (Windows OS-user isolation; elevated terminal) | supported (`--isolated` whole-root; concurrent IDE windows share one OS-user sign-in) | supported (`--isolated` whole-root; concurrent IDE windows share one OS-user sign-in) |
| `zed` | Zed | credential store scoped to an owned OS user | none | supported (Windows OS-user isolation; elevated terminal) | unsupported — owned-user GUI/Keychain session is not proven | unsupported — owned-user GUI/Secret Service session is not implemented |
| `windsurf` | Devin Desktop / Windsurf | separate OS user, or whole-root `--isolated` | none | supported (Windows OS-user isolation; elevated terminal) | supported (`--isolated` whole-root; concurrent IDE windows share one OS-user sign-in) | supported (`--isolated` whole-root; concurrent IDE windows share one OS-user sign-in) |
| `copilot-cli` | GitHub Copilot CLI | per-process `COPILOT_GITHUB_TOKEN` | Copilot configuration and session state | supported (process token via `multi-cli auth set`; `GH_TOKEN`/`GITHUB_TOKEN` cleared) | supported | supported |
| `copilot-vscode` | Copilot in VS Code | separate OS user (GitHub auth in the OS store) | none | supported (Windows OS-user isolation; elevated terminal) | unsupported — owned-user GUI/Keychain session is not proven | unsupported — owned-user GUI/Secret Service session is not implemented |
| `kimi-cli` | Kimi Code CLI direct provider | per-process `KIMI_MODEL_API_KEY` | documented config files | supported (process token via `multi-cli auth set`) | supported | supported |
| `codex-gui` | Codex desktop GUI | owned Windows user and Credential Manager | none | experimental (per-user AppX registration, activation, owner check, and session check) | unsupported; owned-user GUI and Keychain session is not proven | unsupported; no desktop Codex app on Linux |
| `grok-cli` | Grok Build CLI/TUI | per-process `XAI_API_KEY` with precedence preconditions | documented config/sandbox state | supported (process token via `multi-cli auth set`; the shared config must not pin `model.api_key`) | supported | supported |

There is no separately supported first-party Grok Build desktop GUI in the sources reviewed. `grok-cli` covers the official CLI, fullscreen TUI/dashboard, headless mode, and ACP surface.

## Mode notes

- **File overlay** adapters keep only the declared credential files profile-local; everything else links to the native shared root, so conversations and configuration are shared between profiles.
- **Process token** adapters inject a per-profile, highest-precedence credential into the child process only. Store the secret first with `multi-cli auth set <tool>/<profile>`; launch stays fail-closed until then.
- **OS-user isolation** provisions a multi-cli-owned Windows user per profile for products with a fixed Credential Manager identity and requires an elevated terminal. The POSIX account lifecycle exists, but products that need a login Keychain, Secret Service, or desktop session remain unsupported until those sessions are implemented and exercised with the real product.
- **Codex GUI local isolation** separates the Windows profile, Credential Manager, `.codex`, and AppX state. Signing profiles into the same OpenAI account can still show the same server-side conversations and projects. Separate cloud history requires separate OpenAI accounts.
- **`--isolated` whole-root** redirects the product's entire home/config root into the profile dir. It separates filesystem-based products such as `opencode`, `cursor`, Kiro, and Windsurf. It does not isolate fixed OS credential identities, including Claude Code subscription OAuth in the macOS Keychain. Product availability still applies: `--isolated` cannot make an unavailable platform binary supported.
