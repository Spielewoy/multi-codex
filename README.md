# multi-cli

**Run multiple isolated instances of any AI coding tool : simultaneously.**

No more logging in and out. Launch as many sandboxed profiles as you need, each with its own auth, config, sessions, and extensions. Switch between work accounts, client projects, or personal setups instantly.

[![GitHub repository](https://img.shields.io/badge/GitHub-Repository-blue?logo=github)](https://github.com/Spielewoy/multi-codex)
[![GitHub profile](https://img.shields.io/badge/GitHub-Spielewoy-lightgrey?logo=github)](https://github.com/Spielewoy)
[![GitHub stars](https://img.shields.io/github/stars/Spielewoy/multi-codex?style=social)](https://github.com/Spielewoy/multi-codex/stargazers)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](#install)
[![License](https://img.shields.io/badge/license-MIT-green)](#license)

---

🌐 **Language / 语言:**

[![English](https://img.shields.io/badge/lang-English-blue)](#english) [![中文](https://img.shields.io/badge/lang-中文-red)](#中文)

---

<a id="english"></a>

## 🇬🇧 English

### Supported Tools

| Tool | Kind | Isolation | Status |
|------|------|-----------|--------|
| [Claude Code](claude-cli/) | CLI | `env` (`CLAUDE_CONFIG_DIR`) | stable |
| [OpenAI Codex CLI](codex/) | CLI | `env` (`CODEX_HOME`) | stable |
| [OpenCode](opencode/) | CLI | `env` (`OPENCODE_CONFIG_DIR`) | stable |
| [Gemini CLI](gemini-cli/) | CLI | `env` (`GEMINI_CLI_HOME`) | stable |
| [Command Code](commandcode/) | CLI | `redirectHome` | stable |
| [Cursor](cursor/) | IDE | `userDataDir` | stable |
| Antigravity | IDE | `sandboxUser` | archived (requires admin, see `archive/`) |
| AGY-CLI | CLI | `sandboxUser` | archived (requires admin, see `archive/`) |

Each tool has its own folder at the repo root with an `adapter.json` describing how isolation works.

---

### Install

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-codex/main/scripts/install.sh | bash
```

**Windows** — open PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-codex/main/scripts/install.ps1 | iex
```

> After install, **restart your terminal** for PATH changes to take effect.

#### From source

```bash
git clone https://github.com/Spielewoy/multi-codex.git
cd multi-codex
./scripts/install.sh --local        # macOS/Linux
.\scripts\install.ps1 -Local        # Windows
```

> After install, **restart your terminal** for PATH changes to take effect.

> [jq](https://jqlang.github.io/jq/) is **installed automatically** by the installer on all platforms — no manual setup required.

---

### Quick Start

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
| Windows | Start Menu shortcuts created automatically |

---

### Commands

#### Profile Management

| Command | Description |
|---------|-------------|
| `multi-cli new <tool>/<name>` | Create a new isolated profile |
| `multi-cli new <tool>/<name> --shared` | Lightweight profile (shared settings, isolated auth) |
| `multi-cli new <tool>/<name> --from <tpl>` | Create from a saved template |
| `multi-cli <tool>/<name>` | Launch a profile (shorthand) |
| `multi-cli launch <tool>/<name>` | Launch a profile |
| `multi-cli list [<tool>]` | List all profiles |
| `multi-cli status` | Show running state, type, last used, and size |
| `multi-cli clone <tool>/<src> <tool>/<dest>` | Copy an existing profile |
| `multi-cli rename <tool>/<old> <tool>/<new>` | Rename a profile |
| `multi-cli delete <tool>/<name>` | Delete a profile and all its data |

#### Templates

| Command | Description |
|---------|-------------|
| `multi-cli template save <tool>/<profile> <name>` | Save a profile as a reusable template |
| `multi-cli template list` | List saved templates |
| `multi-cli template delete <name>` | Remove a template |

#### Backup & Transfer

| Command | Description |
|---------|-------------|
| `multi-cli export <tool>/<name> [path]` | Archive a profile to `.tar.gz` (`.zip` on Windows) |
| `multi-cli import <archive> <tool>/<name>` | Restore a profile from an archive |

#### Sessions

| Command | Description |
|---------|-------------|
| `multi-cli continue <tool> <src> <dest>` | Copy conversation state (sessions/transcripts/history) from one profile to another — never credentials |
| `multi-cli continue <tool> <src> <dest> --no-merge` | Overwrite destination files instead of keeping newer ones |
| `multi-cli continue <tool> <src> <dest> --dry-run` | Preview what would be copied, change nothing |

`base` works as a profile name on either end and means the tool's real home dir (`~/.codex`, `~/.claude`, …). Supported for `codex`, `claude-cli`, `gemini-cli`, and `commandcode`. See [Continue a Chat Across Accounts](#continue-a-chat-across-accounts).

#### Utilities

| Command | Description |
|---------|-------------|
| `multi-cli tools` | List all supported tools and their install status |
| `multi-cli stats` | Show disk usage per profile |
| `multi-cli doctor` | Diagnose your environment |
| `multi-cli completion {bash\|zsh\|powershell}` | Set up shell tab-completion |
| `multi-cli help` | Show help |
| `multi-cli version` | Show version |

---

### How Isolation Works

multi-cli uses five isolation strategies depending on what the tool supports:

| Strategy | How it works | Used by |
|----------|-------------|---------|
| `env` | Sets a config-dir environment variable before launch | Claude Code, Codex, OpenCode, Gemini CLI |
| `userDataDir` | Passes `--user-data-dir` and `--extensions-dir` flags | Cursor |
| `redirectHome` | Points `HOME`/`USERPROFILE` at a per-profile dir, symlinks shared dotfiles back | Command Code |
| `appdata` | Redirects `%APPDATA%` only (Windows) | *(available but unused)* |
| `sandboxUser` | Creates a dedicated OS user per profile for complete credential/keychain isolation | *(available but unused)* |

Each tool's `<id>/adapter.json` declares which strategy to use.

---

<a id="continue-a-chat-across-accounts"></a>

### Continue a Chat Across Accounts

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

> New profiles are seeded from `base` by default — conversation state, plus skills/config assets for full profiles. Pass `--no-seed` to `multi-cli new` to start empty.

---

### Profile Types

| Flag | Meaning |
|------|---------|
| *(none)* | **Full** — completely isolated. Fresh auth, fresh config. |
| `--shared` | **Shared** — symlinks settings/extensions from your main install. Auth stays isolated. |
| `--cli` | **CLI** — marks the profile for terminal-only launch (skips GUI discovery). |
| `--from <tpl>` | Clone from a saved template. |

---

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `MULTICLI_HOME` | `~/MultiCliProfiles` | Where all profiles are stored |
| `MULTICLI_OVERRIDE_BINARY` | *(unset)* | Force a specific binary path for the next launch |
| `MULTICLI_REPO` | *(unset)* | Git URL for remote install |
| `MULTICLI_PLATFORM` | *(auto)* | Override platform detection (`darwin`, `linux`) |

---

### Diagnostics

```bash
multi-cli doctor
```

Checks that your profile storage exists, alias directory is in PATH, and each tool's binary is detected (or shows an install hint).

---

### Shell Completion

```bash
multi-cli completion bash   # or zsh, powershell
```

Follow the instructions to add it to your `.zshrc`, `.bashrc`, or PowerShell `$PROFILE`.

---

### Uninstall

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-codex/main/scripts/uninstall.sh | bash
```

**Windows**

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-codex/main/scripts/uninstall.ps1 | iex
```

You'll be asked whether to remove your profile data — nothing is deleted without confirmation.

---

### Credits

- **Creator** — [Spielewoy](https://github.com/Spielewoy)

---

### License

[MIT](LICENSE)

---

<a id="中文"></a>

## 🇨🇳 中文

**同时运行多个隔离的 AI 编程工具实例。**

不再需要反复登入登出。启动任意数量的沙盒配置文件，每个都拥有独立的认证、配置、会话和扩展。在工作账户、客户项目或个人设置之间即时切换。

---

### 支持的工具

| 工具 | 类型 | 隔离方式 | 状态 |
|------|------|----------|------|
| [Claude Code](claude-cli/) | CLI | `env` (`CLAUDE_CONFIG_DIR`) | 稳定 |
| [OpenAI Codex CLI](codex/) | CLI | `env` (`CODEX_HOME`) | 稳定 |
| [OpenCode](opencode/) | CLI | `env` (`OPENCODE_CONFIG_DIR`) | 稳定 |
| [Gemini CLI](gemini-cli/) | CLI | `env` (`GEMINI_CLI_HOME`) | 稳定 |
| [Command Code](commandcode/) | CLI | `redirectHome` | 稳定 |
| [Cursor](cursor/) | IDE | `userDataDir` | 稳定 |
| Antigravity | IDE | `sandboxUser` | 已归档（需要管理员权限，见 `archive/`） |
| AGY-CLI | CLI | `sandboxUser` | 已归档（需要管理员权限，见 `archive/`） |

---

### 安装

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-codex/main/scripts/install.sh | bash
```

**Windows** — 打开 PowerShell 运行：

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-codex/main/scripts/install.ps1 | iex
```

> 安装后，**请重启终端** 以使 PATH 更改生效。

#### 从源码安装

```bash
git clone https://github.com/Spielewoy/multi-codex.git
cd multi-codex
./scripts/install.sh --local        # macOS/Linux
.\scripts\install.ps1 -Local        # Windows
```

> 安装后，**请重启终端** 以使 PATH 更改生效。

> 安装程序会在所有平台上**自动安装** [jq](https://jqlang.github.io/jq/) — 无需手动设置。

---

### 快速开始

```bash
# 创建配置文件
multi-cli new claude-cli/work

# 启动
multi-cli launch claude-cli/work

# 或使用简写
multi-cli claude-cli/work
```

每个配置文件都会获得一个自动 shell 别名：

| 平台 | 位置 |
|------|------|
| macOS / Linux | `~/MultiCliProfiles/bin/`（添加到 `PATH`） |
| Windows | 自动创建开始菜单快捷方式 |

---

### 命令

#### 配置文件管理

| 命令 | 说明 |
|------|------|
| `multi-cli new <工具>/<名称>` | 创建新的隔离配置文件 |
| `multi-cli new <工具>/<名称> --shared` | 轻量配置文件（共享设置，隔离认证） |
| `multi-cli new <工具>/<名称> --from <模板>` | 从模板创建 |
| `multi-cli <工具>/<名称>` | 启动配置文件（简写） |
| `multi-cli launch <工具>/<名称>` | 启动配置文件 |
| `multi-cli list [<工具>]` | 列出所有配置文件 |
| `multi-cli status` | 显示运行状态、类型、最后使用时间和大小 |
| `multi-cli clone <工具>/<源> <工具>/<目标>` | 复制配置文件 |
| `multi-cli rename <工具>/<旧名> <工具>/<新名>` | 重命名配置文件 |
| `multi-cli delete <工具>/<名称>` | 删除配置文件及其所有数据 |

#### 模板

| 命令 | 说明 |
|------|------|
| `multi-cli template save <工具>/<配置文件> <名称>` | 将配置文件保存为可复用模板 |
| `multi-cli template list` | 列出已保存的模板 |
| `multi-cli template delete <名称>` | 删除模板 |

#### 备份与迁移

| 命令 | 说明 |
|------|------|
| `multi-cli export <工具>/<名称> [路径]` | 归档为 `.tar.gz`（Windows 为 `.zip`） |
| `multi-cli import <归档文件> <工具>/<名称>` | 从归档恢复配置文件 |

#### 会话

| 命令 | 说明 |
|------|------|
| `multi-cli continue <工具> <源> <目标>` | 将会话状态（会话/记录/历史）从一个配置文件复制到另一个 — 绝不复制凭证 |
| `multi-cli continue <工具> <源> <目标> --no-merge` | 覆盖目标文件，而非保留较新的文件 |
| `multi-cli continue <工具> <源> <目标> --dry-run` | 预览将复制的内容，不做任何更改 |

`base` 在源端或目标端均可作为配置文件名，表示工具的真实主目录（`~/.codex`、`~/.claude` 等）。支持 `codex`、`claude-cli`、`gemini-cli` 和 `commandcode`。详见 [跨账户继续聊天](#跨账户继续聊天)。

#### 实用工具

| 命令 | 说明 |
|------|------|
| `multi-cli tools` | 列出所有支持的工具及安装状态 |
| `multi-cli stats` | 显示每个配置文件的磁盘使用量 |
| `multi-cli doctor` | 诊断环境 |
| `multi-cli completion {bash\|zsh\|powershell}` | 设置 shell 补全 |
| `multi-cli help` | 显示帮助 |
| `multi-cli version` | 显示版本 |

---

### 隔离原理

multi-cli 根据工具支持情况使用五种隔离策略：

| 策略 | 工作方式 | 使用者 |
|------|----------|--------|
| `env` | 启动前设置配置目录环境变量 | Claude Code, Codex, OpenCode, Gemini CLI |
| `userDataDir` | 传递 `--user-data-dir` 和 `--extensions-dir` 参数 | Cursor |
| `redirectHome` | 将 `HOME`/`USERPROFILE` 指向配置文件目录，共享 dotfiles 通过符号链接 | Command Code |
| `appdata` | 仅重定向 `%APPDATA%`（Windows） | *（可用但未使用）* |
| `sandboxUser` | 为每个配置文件创建专用操作系统用户，实现完全的凭证/钥匙串隔离 | *（可用但未使用）* |

每个工具的 `<id>/adapter.json` 声明使用哪种策略。

---

<a id="跨账户继续聊天"></a>

### 跨账户继续聊天

对话进行到一半，账户 A 触发了速率限制？切换到登录账户 B 的配置文件，从中断处接着聊。`multi-cli continue` 会在配置文件之间复制可移植的会话状态 — 会话、记录、历史。**凭证绝不会被复制。**

```bash
# 你原本在 codex/work（账户 A）工作并触发了速率限制。
# codex/personal 登录的是账户 B。
multi-cli continue codex work personal          # 复制会话状态
multi-cli continue codex work personal --dry-run  # 如需，可先预览

codex-personal                                  # 启动账户 B 的配置文件
codex resume <session-id>                        # 继续同一聊天（codex ≥ 0.30）
```

直接运行 `codex resume`（不带参数）会打开历史会话的交互式选择器，无需查找 id。若确实需要，session id 即 `sessions/YYYY/MM/DD/` 下 rollout 文件名中的 UUID。

`base` 在源端或目标端均可作为配置文件名，表示工具的真实主目录（`~/.codex`、`~/.claude` 等），因此可以继续到默认安装或从默认安装继续。

默认情况下文件会**合并** — 保留目标中较新的文件。传入 `--no-merge` 改为覆盖目标，或 `--dry-run` 仅预览而不做更改。

复制后，在目标配置文件内用工具自身的命令继续：

| 工具 | 继续命令 |
|------|----------|
| codex | `codex resume <session-id>`（≥ 0.30） |
| claude-cli | `claude --resume <session-id>`（在同一项目目录下运行） |
| gemini-cli | `gemini --resume`（自动保存的上次会话）或 `/chat resume <tag>`（已保存的检查点） |
| commandcode | 从同一工作目录启动 |

**不支持：** `opencode`（会话与凭证共用一个 SQLite 数据库）和 `cursor`（聊天存储在按工作区路径键控的 SQLite 中）。

> 新配置文件默认从 `base` 播种 — 会话状态，以及完全配置文件的技能/配置资源。向 `multi-cli new` 传入 `--no-seed` 可从空白开始。

---

### 配置文件类型

| 参数 | 含义 |
|------|------|
| *（无）* | **完全隔离** — 全新的认证和配置。 |
| `--shared` | **共享** — 符号链接主安装的设置/扩展，认证保持隔离。 |
| `--cli` | **CLI** — 标记为仅终端启动（跳过 GUI 发现）。 |
| `--from <模板>` | 从已保存的模板克隆。 |

---

### 环境变量

| 变量 | 默认值 | 用途 |
|------|--------|------|
| `MULTICLI_HOME` | `~/MultiCliProfiles` | 所有配置文件的存储位置 |
| `MULTICLI_OVERRIDE_BINARY` | *（未设置）* | 强制指定下次启动的二进制路径 |
| `MULTICLI_REPO` | *（未设置）* | 远程安装的 Git URL |
| `MULTICLI_PLATFORM` | *（自动）* | 覆盖平台检测（`darwin`、`linux`） |

---

### 诊断

```bash
multi-cli doctor
```

检查配置文件存储是否存在、别名目录是否在 PATH 中、以及每个工具的二进制文件是否被检测到（或显示安装提示）。

---

### Shell 补全

```bash
multi-cli completion bash   # 或 zsh、powershell
```

按照提示将其添加到 `.zshrc`、`.bashrc` 或 PowerShell `$PROFILE` 中。

---

### 卸载

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-codex/main/scripts/uninstall.sh | bash
```

**Windows**

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-codex/main/scripts/uninstall.ps1 | iex
```

卸载前会询问是否删除配置文件数据 — 未经确认不会删除任何内容。

---

### 致谢

- **创建者** — [Spielewoy](https://github.com/Spielewoy)

---

### 许可证

[MIT](LICENSE)
