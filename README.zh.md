[English](README.md) | [Español](README.es.md) | [العربية](README.ar.md) | **中文** | [Русский](README.ru.md) | [עברית](README.he.md)

# multi-cli

**同时运行多个 AI 编程工具的账户配置。**

Schema-v2 配置文件会隔离账户凭证与配额，并在边界安全时共享会话、配置和扩展。若厂商将认证与会话绑定，multi-cli 会使用独立的操作系统用户，或通过 `--isolated` 创建整根隔离配置文件。[支持矩阵](docs/support-matrix.md)列出每个平台的准确模式和前置条件。

现有的 schema-v1 配置文件在迁移之前仍为旧版整根配置文件 — 见[旧版配置文件](#旧版配置文件)。

[![GitHub repository](https://img.shields.io/badge/GitHub-Repository-blue?logo=github)](https://github.com/Spielewoy/multi-cli)
[![GitHub profile](https://img.shields.io/badge/GitHub-Spielewoy-lightgrey?logo=github)](https://github.com/Spielewoy)
[![GitHub stars](https://img.shields.io/github/stars/Spielewoy/multi-cli?style=social)](https://github.com/Spielewoy/multi-cli/stargazers)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](#安装)
[![License](https://img.shields.io/badge/license-MIT-green)](#许可证)

---

## 支持的工具

本仓库包含 17 个适配器。`supported` 表示 multi-cli 在该系统上至少提供一种可用的隔离模式；`experimental` 表示实现已可用，但仍需在真实系统上完成所述验证；`unsupported` 表示产品或隔离模式在该系统上不可用。权威来源为 [docs/support-matrix.md](docs/support-matrix.md)。

| 工具 | 类型 | Windows | macOS | Linux |
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
| [Codex Desktop App](codex-gui/) | GUI | experimental (secondary-user AppX launch with owner and session checks; real Windows E2E required) | unsupported (owned-user GUI/Keychain session not proven) | unsupported (no desktop app) |
| [Grok Build CLI](grok-cli/) | CLI/TUI | supported (process token via `multi-cli auth set`) | supported | supported |

每个工具在仓库根目录下都有自己的文件夹，其中的 `adapter.json` 描述了账户边界、共享的正常状态以及升级为“已验证”所需的证据。

---

## 安装

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.sh | bash
```

**Windows** — 打开 PowerShell：

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.ps1 | iex
```

> 安装后，**请重启终端**以使 PATH 更改生效。

### 从源码安装

```bash
git clone https://github.com/Spielewoy/multi-cli.git
cd multi-cli
./scripts/install.sh --local        # macOS/Linux
.\scripts\install.ps1 -Local        # Windows
```

> 安装后，**请重启终端**以使 PATH 更改生效。

> 安装程序会在所有平台上**自动安装** [jq](https://jqlang.github.io/jq/) — 无需手动设置。

---

## 快速开始

```bash
# Create a profile
multi-cli new claude-cli/work

# Launch it
multi-cli launch claude-cli/work

# Or use the shorthand
multi-cli claude-cli/work
```

每个配置文件都会获得一个自动生成的 shell 别名：

| 平台 | 位置 |
|------|------|
| macOS / Linux | `~/MultiCliProfiles/bin/`（添加到 `PATH`） |
| Windows | 自动创建开始菜单快捷方式 |

---

## 命令

### 配置文件管理

| 命令 | 说明 |
|------|------|
| `multi-cli new <tool>/<name>` | 创建账户配置文件（凭据独立，常规状态共享） |
| `multi-cli new <tool>/<name> --isolated` | 创建不共享任何状态的整根隔离配置文件 |
| `multi-cli new <tool>/<name> --shared` | 旧版 schema-v1 共享配置文件；schema-v2 配置文件默认已共享声明的常规状态 |
| `multi-cli new <tool>/<name> --from <tpl>` | 从已保存的模板创建 |
| `multi-cli <tool>/<name>` | 启动配置文件（简写） |
| `multi-cli launch <tool>/<name>` | 启动配置文件 |
| `multi-cli list [<tool>]` | 列出所有配置文件 |
| `multi-cli status` | List profiles with their type and disk size |
| `multi-cli clone <tool>/<src> <tool>/<dest>` | 复制现有配置文件 |
| `multi-cli rename <tool>/<old> <tool>/<new>` | 重命名配置文件 |
| `multi-cli delete <tool>/<name>` | 删除配置文件及其所有数据 |

### 账户认证与迁移

| 命令 | 说明 |
|------|------|
| `multi-cli auth set <tool>/<profile>` | 将配置文件的进程级密钥凭证存入操作系统凭证存储（交互式提示，或从 stdin 读取一行） |
| `multi-cli auth status <tool>/<profile>` | 报告配置文件是否已存储凭证 |
| `multi-cli auth clear <tool>/<profile>` | 删除已存储的凭证 |
| `multi-cli migrate <tool>/<name> [--dry-run] [--prefer-profile]` | 将旧版 schema-v1 配置文件迁移到 schema-v2 |

`auth` 仅适用于使用 `processSecret` 机制的适配器（`cursor-cli`、`copilot-cli`、`kimi-cli`、`grok-cli`）。在存入凭证之前，启动将保持禁用状态。关于 `migrate`，请见[旧版配置文件](#旧版配置文件)。

### 模板

| 命令 | 说明 |
|------|------|
| `multi-cli template save <tool>/<profile> <name>` | 将配置文件保存为可复用模板 |
| `multi-cli template list` | 列出已保存的模板 |
| `multi-cli template delete <name>` | 删除模板 |

### 备份与迁移传输

| 命令 | 说明 |
|------|------|
| `multi-cli export <tool>/<name> [path]` | 将配置文件归档为 `.tar.gz`（Windows 为 `.zip`） |
| `multi-cli import <archive> <tool>/<name>` | 从归档恢复配置文件 |

### 会话

| 命令 | 说明 |
|------|------|
| `multi-cli continue <tool> <src> <dest>` | 将会话状态（会话/记录/历史）从一个配置文件复制到另一个 — 绝不复制凭证 |
| `multi-cli continue <tool> <src> <dest> --no-merge` | 覆盖目标文件，而非保留较新的文件 |
| `multi-cli continue <tool> <src> <dest> --dry-run` | 预览将复制的内容，不做任何更改 |

`base` 在源端或目标端均可作为配置文件名，表示工具的真实主目录（`~/.codex`、`~/.claude` 等）。支持 `codex`、`claude-cli`、`gemini-cli` 和 `commandcode`。详见[跨账户继续聊天](#跨账户继续聊天)。

### 实用工具

| 命令 | 说明 |
|------|------|
| `multi-cli tools` | 列出所有支持的工具及其安装状态 |
| `multi-cli stats` | 显示每个配置文件的磁盘使用量 |
| `multi-cli doctor` | 诊断环境 |
| `multi-cli completion {bash\|zsh\|powershell}` | 设置 shell 补全 |
| `multi-cli help` | 显示帮助 |
| `multi-cli version` | 显示版本 |

---

## 隔离原理

Schema-v2 适配器将账户机制与正常状态分开声明：

| 机制 | 工作方式 |
|------|----------|
| `fileOverlay` | 凭证保留在配置文件内；声明的正常状态链接到工具的原生共享主目录。 |
| `processSecret` | 将每个配置文件独有的、最高优先级的凭证仅注入子进程。在配置好安全的密钥存储之前，启动保持禁用。 |
| `osUserCredentialStore` | Uses a multi-cli-owned OS user for tools with a fixed credential identity. Windows requires elevation; macOS/Linux require `sudo`. |
| `inseparable` | 厂商将认证与正常状态捆绑在一起；合规启动会以失败关闭的方式拒绝，并显示该限制。 |

版本 1 配置文件保留早期的整根 `env`、`userDataDir`、`redirectHome`、`appdata` 和 `sandboxUser` 行为以保持兼容。每个 `<id>/adapter.json` 声明了产品/平台能力和证据要求。

---

<a id="跨账户继续聊天"></a>

## 跨账户继续聊天

对话进行到一半，账户 A 触发了速率限制？切换到登录账户 B 的配置文件，从中断处接着聊。`multi-cli continue` 会在配置文件之间复制可移植的会话状态 — 会话、记录、历史。**凭证绝不会被复制。**

```bash
# You were working in codex/work (account A) and got rate-limited.
# codex/personal is logged into account B.
multi-cli continue codex work personal          # copy the conversation state
multi-cli continue codex work personal --dry-run  # preview first, if you like

codex-personal                                  # launch account B's profile
codex resume <session-id>                        # resume the same chat (codex ≥ 0.30)
```

直接运行 `codex resume`（不带参数）会打开历史会话的交互式选择器，无需查找 id。若确实需要，会话 id 即 `sessions/YYYY/MM/DD/` 下 rollout 文件名中的 UUID。

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

> 旧版 schema-v1 配置文件默认从 `base` 播种。schema-v2 账户配置文件会直接从共享的原生根目录读取声明的会话和配置；隔离配置文件从空白开始。使用 `multi-cli continue` 将支持的会话复制到隔离配置文件或从中复制出来。

---

## 配置文件类型

| 参数 | 含义 |
|------|------|
| *（无）* | **默认共享** — 账户凭证隔离；适配器允许时共享会话和配置。 |
| `-i`、`--isolate`、`--isolated` | **完全隔离** — 工具的整个根目录都在配置文件内，不共享任何内容。 |
| `--shared` | 适配器支持时，共享模式的旧版别名。 |
| `--cli` | **CLI** — 仅从终端启动。 |
| `--from <tpl>` | 从已保存的模板克隆。 |

---

## 环境变量

| 变量 | 默认值 | 用途 |
|------|--------|------|
| `MULTICLI_HOME` | `~/MultiCliProfiles` | 所有配置文件的存储位置 |
| `MULTICLI_OVERRIDE_BINARY` | *（未设置）* | 强制指定下次启动的二进制路径 |
| `MULTICLI_REPO` | *（未设置）* | 远程安装的 Git URL |
| `MULTICLI_PLATFORM` | *（自动）* | 覆盖平台检测（`darwin`、`linux`） |

---

## 旧版配置文件

在 schema-v2 之前创建的配置文件是旧版整根配置文件：它们保留早期的 `env`、`userDataDir`、`redirectHome`、`appdata` 和 `sandboxUser` 行为以保持兼容。没有 `.profile.json` 文件的配置文件目录会被视为旧版。

`multi-cli migrate <tool>/<name>` 将旧版配置文件转换为 schema-v2：声明的凭证移入配置文件，声明的正常状态链接到共享的工具主目录。使用 `--dry-run` 可预览移动计划而不做任何更改；使用 `--prefer-profile` 可用配置文件的副本替换冲突的共享文件 — 凭证目标绝不会被覆盖。配置文件存储与共享状态根目录必须位于同一卷上，因为迁移使用同卷原子移动。

---

## 诊断

```bash
multi-cli doctor
```

检查配置文件存储是否存在、别名目录是否在 PATH 中，以及每个工具的二进制文件是否被检测到（或显示安装提示）。

---

## Shell 补全

```bash
multi-cli completion bash   # or zsh, powershell
```

按照提示将其添加到 `.zshrc`、`.bashrc` 或 PowerShell `$PROFILE` 中。

---

## 卸载

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.sh | bash
```

**Windows**

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.ps1 | iex
```

卸载前会询问是否删除配置文件数据 — 未经确认不会删除任何内容。

---

## 链接

- [支持矩阵](docs/support-matrix.md) — 按产品、按操作系统的隔离状态及验证门槛
- [安全策略](SECURITY.md)
- [许可证](LICENSE)
- [GitHub 仓库](https://github.com/Spielewoy/multi-cli)

---

## 致谢

- **创建者** — [Spielewoy](https://github.com/Spielewoy)

---

## 许可证

[MIT](LICENSE)
