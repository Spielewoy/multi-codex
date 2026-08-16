**English** | [Español](README.es.md) | [العربية](README.ar.md) | [中文](README.zh.md) | [Русский](README.ru.md) | [עברית](README.he.md)

# multi-cli

**Run multiple account profiles for AI coding tools simultaneously.**

By default, each profile gets separate account credentials while conversations, configuration, agents, skills, and plugins stay shared where the tool allows it. Use `--isolated` when you want the entire tool home separated. Tools whose login cannot be separated safely use OS-user isolation instead. See the [support matrix](docs/support-matrix.md) for per-platform requirements.

Profiles created by older multi-cli versions keep their whole-root behavior until migrated — see [Legacy Profiles](#legacy-profiles).

[![GitHub repository](https://img.shields.io/badge/GitHub-Repository-blue?logo=github)](https://github.com/Spielewoy/multi-cli)
[![GitHub profile](https://img.shields.io/badge/GitHub-Spielewoy-lightgrey?logo=github)](https://github.com/Spielewoy)
[![GitHub stars](https://img.shields.io/github/stars/Spielewoy/multi-cli?style=social)](https://github.com/Spielewoy/multi-cli/stargazers)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](#install)
[![License](https://img.shields.io/badge/license-MIT-green)](#license)

---

## Supported Tools

17 adapters ship in this repository. Status is per operating system and binary: `supported` means multi-cli provides account isolation on that OS (any mode requirements are noted), and `unsupported` means no isolation mode works there. The authoritative source is [docs/support-matrix.md](docs/support-matrix.md).

| Tool | Kind | Windows | macOS | Linux |
|------|------|---------|-------|-------|
| [Claude Code](claude-cli/) | CLI | supported (file overlay) | supported for API-key profiles only; subscription OAuth is unsupported | supported (file overlay) |
| [OpenAI Codex CLI](codex/) | CLI | supported (file overlay; file credential store mode) | supported | supported |
| [Gemini CLI](gemini-cli/) | CLI | supported (file overlay) | supported | supported |
| [OpenCode](opencode/) | CLI | supported (`--isolated` whole-root) | supported (`--isolated` whole-root) | supported (`--isolated` whole-root) |
| [Command Code](commandcode/) | CLI | supported (file overlay; use `commandcode`, bare `cmd` collides with cmd.exe) | supported | supported |
| [Cursor Desktop](cursor/) | IDE | supported (`--isolated` whole-root) | supported (`--isolated` whole-root) | supported (`--isolated` whole-root) |
| [Cursor CLI](cursor-cli/) | CLI | supported (process token via `multi-cli auth set`) | supported | supported |
| [Antigravity](antigravity/) | IDE | supported (OS-user isolation; elevated terminal) | unsupported (owned-user GUI/Keychain session not proven) | unsupported (owned-user GUI/Secret Service session not implemented) |
| [AGY CLI](agy-cli/) | CLI | supported (OS-user isolation; elevated terminal) | unsupported (owned-user Keychain isolation not proven) | unsupported (owned-user Secret Service session not implemented) |
| [Kiro](kiro/) | IDE | supported (OS-user isolation) | supported (`--isolated` whole-root) | supported (`--isolated` whole-root) |
| [Zed](zed/) | IDE | supported (OS-user isolation; elevated terminal) | unsupported (owned-user GUI/Keychain session not proven) | unsupported (owned-user GUI/Secret Service session not implemented) |
| [Devin Desktop / Windsurf](windsurf/) | IDE | supported (OS-user isolation; elevated terminal) | supported (`--isolated` whole-root) | supported (`--isolated` whole-root) |
| [GitHub Copilot CLI](copilot-cli/) | CLI | supported (process token via `multi-cli auth set`) | supported | supported |
| [Copilot in VS Code](copilot-vscode/) | IDE | supported (OS-user isolation; elevated terminal) | unsupported (owned-user GUI/Keychain session not proven) | unsupported (owned-user GUI/Secret Service session not implemented) |
| [Kimi Code CLI](kimi-cli/) | CLI | supported (process token via `multi-cli auth set`) | supported | supported |
| [Codex Desktop App](codex-gui/) | GUI | supported (owned Windows user and Store AppX activation) | unsupported (owned-user GUI/Keychain session not proven) | unsupported (no desktop app) |
| [Grok Build CLI](grok-cli/) | CLI/TUI | supported (process token via `multi-cli auth set`) | supported | supported |

Each tool has its own folder at the repo root with an `adapter.json` describing the account boundary, the shared normal state, and the per-OS support status.

---

## Install

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.sh | bash
```

**Windows** — open PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.ps1 | iex
```

> After install, **restart your terminal** for PATH changes to take effect.

### From source

```bash
git clone https://github.com/Spielewoy/multi-cli.git
cd multi-cli
./scripts/install.sh --local        # macOS/Linux
.\scripts\install.ps1 -Local        # Windows
```

> After install, **restart your terminal** for PATH changes to take effect.

> [jq](https://jqlang.github.io/jq/) is **installed automatically** by the installer on all platforms — no manual setup required.

---

## Quick Start

```bash
# Create a profile
multi-cli new claude-cli/work

# Launch it
multi-cli launch claude-cli/work

# Or use the shorthand
multi-cli claude-cli/work
```

Each profile gets an automatic shell alias:

| Platform | Location |
|----------|----------|
| macOS / Linux | `~/MultiCliProfiles/bin/` (add to `PATH`) |
| Windows | CLI aliases in `~/MultiCliProfiles/bin/`; Start Menu shortcuts for GUI profiles |

---

## Commands

### Profile Management

| Command | Description |
|---------|-------------|
| `multi-cli new <tool>/<name>` | Create an account profile (credentials separate; normal state shared) |
| `multi-cli new <tool>/<name> --isolated` | Fully isolated schema-v2 profile — shares nothing (whole tool root inside the profile) |
| `multi-cli new <tool>/<name> --shared` | Legacy schema-v1 shared profile; schema-v2 profiles already share declared normal state by default |
| `multi-cli new <tool>/<name> --from <tpl>` | Create from a saved template |
| `multi-cli <tool>/<name>` | Launch a profile (shorthand) |
| `multi-cli launch <tool>/<name>` | Launch a profile |
| `multi-cli list [<tool>]` | List all profiles |
| `multi-cli status` | List profiles with their type and disk size |
| `multi-cli clone <tool>/<src> <tool>/<dest>` | Copy an existing profile |
| `multi-cli rename <tool>/<old> <tool>/<new>` | Rename a profile |
| `multi-cli delete <tool>/<name>` | Delete a profile and all its data |

### Account Authentication & Migration

| Command | Description |
|---------|-------------|
| `multi-cli auth set <tool>/<profile>` | Store the profile's process-secret credential in the OS credential store (prompts interactively, or reads one line from stdin) |
| `multi-cli auth status <tool>/<profile>` | Report whether a credential is stored for the profile |
| `multi-cli auth clear <tool>/<profile>` | Remove the stored credential |
| `multi-cli migrate <tool>/<name> [--dry-run] [--prefer-profile]` | Migrate a legacy schema-v1 profile to schema-v2 |

`auth` applies only to adapters that use the `processSecret` mechanism (`cursor-cli`, `copilot-cli`, `kimi-cli`, `grok-cli`). Launch stays disabled until a credential is stored. See [Legacy Profiles](#legacy-profiles) for `migrate`.

### Templates

| Command | Description |
|---------|-------------|
| `multi-cli template save <tool>/<profile> <name>` | Save a profile as a reusable template |
| `multi-cli template list` | List saved templates |
| `multi-cli template delete <name>` | Remove a template |

### Backup & Transfer

| Command | Description |
|---------|-------------|
| `multi-cli export <tool>/<name> [path]` | Archive a profile to `.tar.gz` (`.zip` on Windows) |
| `multi-cli import <archive> <tool>/<name>` | Restore a profile from an archive |

### Sessions

| Command | Description |
|---------|-------------|
| `multi-cli continue <tool> <src> <dest>` | Copy conversation state (sessions/transcripts/history) from one profile to another — never credentials |
| `multi-cli continue <tool> <src> <dest> --no-merge` | Overwrite destination files instead of keeping newer ones |
| `multi-cli continue <tool> <src> <dest> --dry-run` | Preview what would be copied, change nothing |

`base` works as a profile name on either end and means the tool's real home dir (`~/.codex`, `~/.claude`, …). Supported for `codex`, `claude-cli`, `gemini-cli`, and `commandcode`. See [Continue a Chat Across Accounts](#continue-a-chat-across-accounts).

### Utilities

| Command | Description |
|---------|-------------|
| `multi-cli tools` | List all supported tools and their install status |
| `multi-cli stats` | Show disk usage per profile |
| `multi-cli doctor` | Diagnose your environment |
| `multi-cli completion {bash\|zsh\|powershell}` | Set up shell tab-completion |
| `multi-cli help` | Show help |
| `multi-cli version` | Show version |

---

## How Isolation Works

Schema-v2 adapters declare an account mechanism separately from normal state:

| Mechanism | How it works |
|-----------|--------------|
| `fileOverlay` | Credentials stay under the profile; declared normal state links to the native shared tool home. |
| `processSecret` | A per-profile, highest-precedence credential is injected into only the child process. Launch remains disabled until secure secret storage is configured. |
| `osUserCredentialStore` | Fixed keychain identities are separated with a multi-cli-owned OS user. Provisioning requires an elevated terminal on Windows. |
| `inseparable` | The vendor combines auth and normal state; compliant launch fails closed and the limitation is shown. |

Version-1 profiles retain the earlier whole-root `env`, `userDataDir`, `redirectHome`, `appdata`, and `sandboxUser` behavior for compatibility. Each `<id>/adapter.json` states product/platform capabilities and per-OS support status.

---

## Shared vs Isolated Profiles

Profiles are **shared** by default: account credentials are separate, while conversations, configuration, and skills use the tool's normal shared location. `--isolated` puts the tool's entire home/config directory inside the profile, so nothing is shared. Isolated profiles can still be used with `continue` to copy supported conversations between accounts. For tools whose login cannot be split from normal state, `--isolated` is the direct whole-root option and avoids creating a separate OS user.

```bash
multi-cli new codex/acme --isolated   # CODEX_HOME is the profile dir; ~/.codex is never touched
```

---

<a id="continue-a-chat-across-accounts"></a>

## Continue a Chat Across Accounts

Hit a rate limit on account A mid-conversation? Switch to a profile logged into account B and pick the chat up where it stopped. `multi-cli continue` copies the portable conversation state — sessions, transcripts, history — between profiles. **Credentials are never copied.**

```bash
# You were working in codex/work (account A) and got rate-limited.
# codex/personal is logged into account B.
multi-cli continue codex work personal          # copy the conversation state
multi-cli continue codex work personal --dry-run  # preview first, if you like

codex-personal                                  # launch account B's profile
codex resume <session-id>                        # resume the same chat (codex ≥ 0.30)
```

Run `codex resume` with no argument to open an interactive picker of past sessions, so you never have to look up an id. If you do need it, the session id is the UUID in the rollout filename under `sessions/YYYY/MM/DD/`.

`base` is a valid profile name on either end and refers to the tool's real home dir (`~/.codex`, `~/.claude`, …), so you can continue to or from your default install.

By default, files are **merged** — newer files in the destination are kept. Pass `--no-merge` to overwrite the destination instead, or `--dry-run` to preview without changing anything.

After copying, resume inside the destination profile with the tool's own command:

| Tool | Resume command |
|------|----------------|
| codex | `codex resume <session-id>` (≥ 0.30) |
| claude-cli | `claude --resume <session-id>` (run from the same project directory) |
| gemini-cli | `gemini --resume` (auto-saved last session) or `/chat resume <tag>` for saved checkpoints |
| commandcode | launch from the same working directory |

**Not supported:** `opencode` (sessions and credentials live in one shared SQLite database) and `cursor` (chats are stored in SQLite keyed to the workspace path).

> Legacy schema-v1 profiles are seeded from `base` by default. Schema-v2 account profiles already read declared conversations and configuration from the shared native root; isolated profiles start empty. Use `multi-cli continue` to copy supported conversations into or out of an isolated profile.

---

## Profile Types

| Flag | Meaning |
|------|---------|
| *(none)* | **Account profile** — separate credentials with declared conversations/config shared through the native tool root. |
| `--isolated`, `--isolate`, `-i` | **Whole-root isolated** — shares nothing with the native tool root. |
| `--shared` | **Legacy shared profile** — links settings/extensions for schema-v1 adapters; cannot be combined with `--isolated`. |
| `--cli` | **CLI** — marks the profile for terminal-only launch (skips GUI discovery). |
| `--from <tpl>` | Create from a validated, credential-free template. |

---

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `MULTICLI_HOME` | `~/MultiCliProfiles` | Where all profiles are stored |
| `MULTICLI_OVERRIDE_BINARY` | *(unset)* | Force a specific binary path for the next launch |
| `MULTICLI_REPO` | *(unset)* | Git URL for remote install |
| `MULTICLI_PLATFORM` | *(auto)* | Override platform detection (`darwin`, `linux`) |

---

## Legacy Profiles

Profiles created before schema-v2 are legacy whole-root profiles: they keep the earlier `env`, `userDataDir`, `redirectHome`, `appdata`, and `sandboxUser` behavior for compatibility. A profile directory without a `.profile.json` file is treated as legacy.

`multi-cli migrate <tool>/<name>` converts a legacy profile to schema-v2: declared credentials move into the profile, and declared normal state links to the shared tool home. Use `--dry-run` to preview the move plan without changing anything, and `--prefer-profile` to replace conflicting shared files with the profile's copy — credential targets are never overwritten. Profile storage and the shared state root must be on the same volume, because migration uses atomic same-volume moves.

---

## Diagnostics

```bash
multi-cli doctor
```

Checks that your profile storage exists, alias directory is in PATH, and each tool's binary is detected (or shows an install hint).

---

## Shell Completion

```bash
multi-cli completion bash   # or zsh, powershell
```

Follow the instructions to add it to your `.zshrc`, `.bashrc`, or PowerShell `$PROFILE`.

---

## Uninstall

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.sh | bash
```

**Windows**

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.ps1 | iex
```

You'll be asked whether to remove your profile data — nothing is deleted without confirmation.

---

## Links

- [Support matrix](docs/support-matrix.md) — per-product, per-OS isolation status and mode requirements
- [Security policy](SECURITY.md)
- [License](LICENSE)
- [GitHub repository](https://github.com/Spielewoy/multi-cli)

---

## Credits

- **Creator** — [Spielewoy](https://github.com/Spielewoy)

---

## License

[MIT](LICENSE)
