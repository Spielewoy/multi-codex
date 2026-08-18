<p align="center">
  <img src="assets/banner.svg" alt="Multi-CLI. Use multiple accounts simultaneously without switching." width="760"/>
</p>

<p align="center">Use multiple accounts simultaneously without switching.</p>

<p align="center">
  <a href="#supported-tools"><img src="https://img.shields.io/badge/support-17%20adapters-255C60?style=flat-square&labelColor=14101F" alt="17 adapters"/></a>
  <a href="https://github.com/Spielewoy/multi-cli/releases/latest"><img src="https://img.shields.io/github/v/release/Spielewoy/multi-cli?style=flat-square&label=version&color=255C60&labelColor=14101F" alt="Version 1.0.0"/></a>
  <a href="#install"><img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-255C60?style=flat-square&labelColor=14101F" alt="macOS, Linux, and Windows"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-255C60?style=flat-square&labelColor=14101F" alt="License MIT"/></a>
</p>

<p align="center">
  <a href="README.md"><b>English</b></a> |
  <a href="docs/translations/es.md">Español</a> |
  <a href="docs/translations/ar.md">العربية</a> |
  <a href="docs/translations/zh.md">中文</a> |
  <a href="docs/translations/ru.md">Русский</a> |
  <a href="docs/translations/he.md">עברית</a>
</p>

## Contents

[Install](#install) · [Quick start](#quick-start) · [Supported tools](#supported-tools) · [Commands](#commands) · [Isolation](#how-isolation-works) · [Move sessions](#move-sessions-between-accounts) · [Troubleshooting](#troubleshooting) · [Uninstall](#uninstall)

## Install

Use the platform install script below, or download a packaged archive from [GitHub Releases](https://github.com/Spielewoy/multi-cli/releases).

### macOS and Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.sh | bash
```

### Windows

Open PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.ps1 | iex
```

The installer clones or updates Multi-CLI and installs `jq` if needed. Rerun the same command to update. Restart your terminal after installation. On macOS and Linux, follow the printed PATH instruction if one appears.

<details>
<summary><strong>Install from source</strong></summary>

```bash
git clone https://github.com/Spielewoy/multi-cli.git
cd multi-cli
./scripts/install.sh --local
```

Windows PowerShell:

```powershell
git clone https://github.com/Spielewoy/multi-cli.git
cd multi-cli
.\scripts\install.ps1 -Local
```

</details>

Requirements: Git, an internet connection, Bash on macOS or Linux, or PowerShell on Windows. The installer resolves the required `jq` binary automatically when possible.

## Quick start

```bash
# Check your setup and discover installed tools
multi-cli doctor
multi-cli tools

# Create and launch a profile
multi-cli new claude-cli/work
multi-cli launch claude-cli/work

# Launch shorthand
multi-cli claude-cli/work
```

By default, credentials stay inside the profile while supported settings, conversations, agents, skills, and plugins remain shared. Add `--isolated` when the whole tool home must be separate.

## Supported tools

| Tool | Adapter | Platforms | Account boundary |
|---|---|---|---|
| AGY CLI | `agy-cli` | Windows | OS user |
| Antigravity | `antigravity` | Windows | OS user |
| Claude Code | `claude-cli` | Windows, Linux, macOS API keys | File overlay |
| Codex CLI | `codex` | Windows, macOS, Linux | File overlay |
| Codex Desktop | `codex-gui` | Windows | OS user |
| Command Code | `commandcode` | Windows, macOS, Linux | File overlay |
| GitHub Copilot CLI | `copilot-cli` | Windows, macOS, Linux | Process secret |
| GitHub Copilot in VS Code | `copilot-vscode` | Windows | OS user |
| Cursor CLI | `cursor-cli` | Windows, macOS, Linux | Process secret |
| Cursor Desktop | `cursor` | Windows, macOS, Linux | Isolated tool home |
| Gemini CLI | `gemini-cli` | Windows, macOS, Linux | File overlay |
| Grok Build CLI | `grok-cli` | Windows, macOS, Linux | Process secret |
| Kimi Code CLI | `kimi-cli` | Windows, macOS, Linux | Process secret |
| Kiro | `kiro` | Windows, macOS, Linux | OS user or isolated tool home |
| OpenCode | `opencode` | Windows, macOS, Linux | Isolated tool home |
| Windsurf | `windsurf` | Windows, macOS, Linux | OS user or isolated tool home |
| Zed | `zed` | Windows | OS user |

Platform requirements and known limits are documented in the [support matrix](docs/support-matrix.md). Run `multi-cli tools` to see what is available on your machine.

## Commands

### Profiles

| Command | Action |
|---|---|
| `multi-cli new <tool>/<name>` | Create an account profile (credentials separate; normal state shared) |
| `multi-cli new <tool>/<name> --isolated` | Create a whole-root isolated profile; aliases: `--isolate`, `-i` |
| `multi-cli new <tool>/<name> --from <template>` | Create a profile from a saved template |
| `multi-cli <tool>/<name>` | Launch a profile |
| `multi-cli launch <tool>/<name> [-- args...]` | Launch and pass arguments to the tool |
| `multi-cli list [<tool>]` | List profiles |
| `multi-cli clone <tool>/<src> <tool>/<dest>` | Copy a profile |
| `multi-cli rename <tool>/<old> <tool>/<new>` | Rename a profile |
| `multi-cli delete <tool>/<name>` | Delete a profile after confirmation |

### Credentials and portability

| Command | Action |
|---|---|
| `multi-cli auth set <tool>/<profile>` | Store a process secret in the OS credential store |
| `multi-cli auth status <tool>/<profile>` | Check whether that secret exists |
| `multi-cli auth clear <tool>/<profile>` | Remove that secret |
| `multi-cli continue <tool> <src> <dest> [--dry-run] [--no-merge]` | Copy supported session state, never credentials |
| `multi-cli template save <tool>/<profile> <name>` | Save a credential-free template |
| `multi-cli template list \| delete <name>` | List or delete templates |
| `multi-cli export <tool>/<name> [path]` | Export a profile |
| `multi-cli import <archive> <tool>/<name>` | Import a profile |

### Maintenance

| Command | Action |
|---|---|
| `multi-cli migrate <tool>/<name> [--dry-run] [--prefer-profile]` | Migrate a legacy profile to schema v2 |
| `multi-cli status` | Show profiles and sizes |
| `multi-cli stats` | Show profile storage use |
| `multi-cli doctor [--deep]` | Diagnose setup and optionally audit runtimes |
| `multi-cli completion {bash\|zsh\|powershell}` | Print shell completion setup |
| `multi-cli help` | Show every command |
| `multi-cli version` | Show the installed version |

## How isolation works

| Mode | What stays separate | What stays shared |
|---|---|---|
| File overlay | Declared credential files | Native configuration and conversations |
| Process secret | One credential injected into the child process | The tool's normal state |
| OS user | The product's fixed OS credential identity | Nothing unless the adapter declares it |
| Isolated tool home | The entire tool home | Nothing |

Account profiles use the narrowest safe boundary. `--isolated` uses a separate tool home and shares nothing. Products tied to a fixed OS credential identity use a Multi-CLI-owned Windows user and require an elevated terminal.

Process-secret adapters require one extra step before launch:

```bash
multi-cli new cursor-cli/work
multi-cli auth set cursor-cli/work
multi-cli cursor-cli/work
```

Profiles created by earlier Multi-CLI versions keep their original whole-root behavior. Preview migration with:

```bash
multi-cli migrate codex/work --dry-run
```

## Move sessions between accounts

Copy supported conversation state when one account reaches a limit:

```bash
multi-cli continue codex work personal --dry-run
multi-cli continue codex work personal
multi-cli codex/personal
codex resume
```

`base` refers to the tool's normal home, so either side can be a profile or the default installation. Credentials are never copied. Session transfer is supported for `codex`, `claude-cli`, `gemini-cli`, and `commandcode`.

## Shell aliases

Each profile gets a shortcut such as `claude-cli-work`.

| Platform | Location |
|---|---|
| macOS and Linux | `~/MultiCliProfiles/bin/` |
| Windows | `~/MultiCliProfiles/bin/`, plus Start Menu shortcuts for GUI profiles |

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `MULTICLI_HOME` | `~/MultiCliProfiles` | Profile storage |
| `MULTICLI_OVERRIDE_BINARY` | unset | Override binary discovery for one launch |
| `MULTICLI_REPO` | GitHub repository | Override the install source |
| `MULTICLI_INSTALL_DIR` | platform default | Override the installation directory |

## Troubleshooting

```bash
multi-cli doctor
multi-cli doctor --deep
multi-cli tools
```

Restart the terminal if `multi-cli` or a new profile alias is not found after installation. The [support matrix](docs/support-matrix.md) covers product-specific requirements.

## Uninstall

macOS and Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.sh | bash
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.ps1 | iex
```

Profile data is preserved unless you confirm its removal.

## Links

- [Support matrix](docs/support-matrix.md)
- [Security policy](docs/SECURITY.md)
- [Contributing](docs/CONTRIBUTING.md)
- [Support](docs/SUPPORT.md)
- [GitHub Releases](https://github.com/Spielewoy/multi-cli/releases)

## License

[MIT](LICENSE)
