<p align="center">
  <img src="../../assets/i18n/zh/banner.svg" alt="Multi-CLI。无需切换，同时使用多个账户。" width="760"/>
</p>

<p align="center">无需切换，同时使用多个账户。</p>

<p align="center">
  <a href="#supported-tools"><img src="https://img.shields.io/badge/support-17%20adapters-255C60?style=flat-square&labelColor=14101F" alt="17 个适配器"/></a>
  <a href="https://github.com/Spielewoy/multi-cli/releases/latest"><img src="https://img.shields.io/github/v/release/Spielewoy/multi-cli?style=flat-square&label=version&color=255C60&labelColor=14101F" alt="版本 1.0.0"/></a>
  <a href="#install"><img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-255C60?style=flat-square&labelColor=14101F" alt="macOS、Linux 和 Windows"/></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-255C60?style=flat-square&labelColor=14101F" alt="MIT 许可证"/></a>
</p>

<p align="center">
  <a href="../../README.md">English</a> |
  <a href="es.md">Español</a> |
  <a href="ar.md">العربية</a> |
  <a href="zh.md"><b>中文</b></a> |
  <a href="ru.md">Русский</a> |
  <a href="he.md">עברית</a>
</p>

## 目录

[安装](#install) · [快速开始](#quick-start) · [支持的工具](#supported-tools) · [命令](#commands) · [隔离机制](#how-isolation-works) · [迁移会话](#move-sessions-between-accounts) · [故障排除](#troubleshooting) · [卸载](#uninstall)

<a id="install"></a>

## 安装

使用下方对应平台的安装脚本，或从 [GitHub Releases](https://github.com/Spielewoy/multi-cli/releases) 下载打包文件。

### macOS 和 Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.sh | bash
```

### Windows

打开 PowerShell：

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.ps1 | iex
```

安装程序会克隆或更新 Multi-CLI，并在需要时安装 `jq`。再次运行同一命令即可更新。安装后请重启终端。在 macOS 和 Linux 上，如果安装程序显示 PATH 设置说明，请按其操作。

<details>
<summary><strong>从源代码安装</strong></summary>

```bash
git clone https://github.com/Spielewoy/multi-cli.git
cd multi-cli
./scripts/install.sh --local
```

Windows PowerShell：

```powershell
git clone https://github.com/Spielewoy/multi-cli.git
cd multi-cli
.\scripts\install.ps1 -Local
```

</details>

要求：Git、互联网连接、macOS 或 Linux 上的 Bash，或 Windows 上的 PowerShell。安装程序会尽可能自动获取所需的 `jq` 可执行文件。

<a id="quick-start"></a>

## 快速开始

```bash
# 检查环境并发现已安装的工具
multi-cli doctor
multi-cli tools

# 创建并启动配置文件
multi-cli new claude-cli/work
multi-cli launch claude-cli/work

# 简写形式
multi-cli claude-cli/work
```

默认情况下，凭据保留在配置文件内，而受支持的设置、对话、代理、技能和插件保持共享。需要隔离整个工具主目录时，请添加 `--isolated`。

<a id="supported-tools"></a>

## 支持的工具

| 工具 | 适配器 | 平台 | 账户边界 |
|---|---|---|---|
| AGY CLI | `agy-cli` | Windows | 操作系统用户 |
| Antigravity | `antigravity` | Windows | 操作系统用户 |
| Claude Code | `claude-cli` | Windows、Linux、macOS API 密钥 | 文件覆盖层 |
| Codex CLI | `codex` | Windows、macOS、Linux | 文件覆盖层 |
| Codex Desktop | `codex-gui` | Windows | 操作系统用户 |
| Command Code | `commandcode` | Windows、macOS、Linux | 文件覆盖层 |
| GitHub Copilot CLI | `copilot-cli` | Windows、macOS、Linux | 进程密钥 |
| VS Code 中的 GitHub Copilot | `copilot-vscode` | Windows | 操作系统用户 |
| Cursor CLI | `cursor-cli` | Windows、macOS、Linux | 进程密钥 |
| Cursor Desktop | `cursor` | Windows、macOS、Linux | 独立工具主目录 |
| Gemini CLI | `gemini-cli` | Windows、macOS、Linux | 文件覆盖层 |
| Grok Build CLI | `grok-cli` | Windows、macOS、Linux | 进程密钥 |
| Kimi Code CLI | `kimi-cli` | Windows、macOS、Linux | 进程密钥 |
| Kiro | `kiro` | Windows、macOS、Linux | 操作系统用户或独立工具主目录 |
| OpenCode | `opencode` | Windows、macOS、Linux | 独立工具主目录 |
| Windsurf | `windsurf` | Windows、macOS、Linux | 操作系统用户或独立工具主目录 |
| Zed | `zed` | Windows | 操作系统用户 |

各平台的要求和已知限制请参阅[支持矩阵](../support-matrix.md)。运行 `multi-cli tools` 可查看本机可用的工具。

<a id="commands"></a>

## 命令

### 配置文件

| 命令 | 操作 |
|---|---|
| `multi-cli new <tool>/<name>` | 创建凭据分离、正常状态共享的账户配置文件 |
| `multi-cli new <tool>/<name> --isolated` | 创建整个主目录均隔离的配置文件；别名：`--isolate`、`-i` |
| `multi-cli new <tool>/<name> --from <template>` | 从已保存的模板创建配置文件 |
| `multi-cli <tool>/<name>` | 启动配置文件 |
| `multi-cli launch <tool>/<name> [-- args...]` | 启动工具并向其传递参数 |
| `multi-cli list [<tool>]` | 列出配置文件 |
| `multi-cli clone <tool>/<src> <tool>/<dest>` | 复制配置文件 |
| `multi-cli rename <tool>/<old> <tool>/<new>` | 重命名配置文件 |
| `multi-cli delete <tool>/<name>` | 确认后删除配置文件 |

### 凭据与可移植性

| 命令 | 操作 |
|---|---|
| `multi-cli auth set <tool>/<profile>` | 将进程密钥存入操作系统凭据存储 |
| `multi-cli auth status <tool>/<profile>` | 检查该密钥是否存在 |
| `multi-cli auth clear <tool>/<profile>` | 删除该密钥 |
| `multi-cli continue <tool> <src> <dest> [--dry-run] [--no-merge]` | 复制受支持的会话状态，绝不复制凭据 |
| `multi-cli template save <tool>/<profile> <name>` | 保存不含凭据的模板 |
| `multi-cli template list \| delete <name>` | 列出或删除模板 |
| `multi-cli export <tool>/<name> [path]` | 导出配置文件 |
| `multi-cli import <archive> <tool>/<name>` | 导入配置文件 |

### 维护

| 命令 | 操作 |
|---|---|
| `multi-cli migrate <tool>/<name> [--dry-run] [--prefer-profile]` | 将旧配置文件迁移到 schema v2 |
| `multi-cli status` | 显示配置文件及其大小 |
| `multi-cli stats` | 显示配置文件的存储占用 |
| `multi-cli doctor [--deep]` | 诊断环境，并可选择审查运行环境 |
| `multi-cli completion {bash\|zsh\|powershell}` | 输出 shell 补全设置 |
| `multi-cli help` | 显示所有命令 |
| `multi-cli version` | 显示已安装的版本 |

<a id="how-isolation-works"></a>

## 隔离机制

| 模式 | 单独保留的内容 | 共享的内容 |
|---|---|---|
| 文件覆盖层 | 声明的凭据文件 | 工具原有的配置和对话 |
| 进程密钥 | 注入子进程的一项凭据 | 工具的正常状态 |
| 操作系统用户 | 产品固定的操作系统凭据身份 | 除非适配器另有声明，否则不共享任何内容 |
| 独立工具主目录 | 整个工具主目录 | 不共享任何内容 |

账户配置文件采用满足安全要求的最小隔离边界。`--isolated` 使用独立的工具主目录，不共享任何内容。绑定到固定操作系统凭据身份的产品会使用由 Multi-CLI 管理的 Windows 用户，并需要以管理员权限运行终端。

使用进程密钥的适配器需要在启动前多执行一步：

```bash
multi-cli new cursor-cli/work
multi-cli auth set cursor-cli/work
multi-cli cursor-cli/work
```

由旧版 Multi-CLI 创建的配置文件会保留原有的完整主目录隔离方式。可使用以下命令预览迁移：

```bash
multi-cli migrate codex/work --dry-run
```

<a id="move-sessions-between-accounts"></a>

## 在账户之间迁移会话

当一个账户达到限额时，复制受支持的对话状态：

```bash
multi-cli continue codex work personal --dry-run
multi-cli continue codex work personal
multi-cli codex/personal
codex resume
```

`base` 表示工具的正常主目录，因此任一端都可以是配置文件或默认安装。凭据绝不会被复制。`codex`、`claude-cli`、`gemini-cli` 和 `commandcode` 支持会话迁移。

## Shell 别名

每个配置文件都会获得一个类似 `claude-cli-work` 的快捷命令。

| 平台 | 位置 |
|---|---|
| macOS 和 Linux | `~/MultiCliProfiles/bin/` |
| Windows | `~/MultiCliProfiles/bin/`，图形界面配置文件还会获得开始菜单快捷方式 |

## 配置

| 变量 | 默认值 | 用途 |
|---|---|---|
| `MULTICLI_HOME` | `~/MultiCliProfiles` | 配置文件存储位置 |
| `MULTICLI_OVERRIDE_BINARY` | 未设置 | 为单次启动覆盖可执行文件发现结果 |
| `MULTICLI_REPO` | GitHub 仓库 | 覆盖安装来源 |
| `MULTICLI_INSTALL_DIR` | 平台默认值 | 覆盖安装目录 |

<a id="troubleshooting"></a>

## 故障排除

```bash
multi-cli doctor
multi-cli doctor --deep
multi-cli tools
```

如果安装后找不到 `multi-cli` 或新配置文件的别名，请重启终端。[支持矩阵](../support-matrix.md)列出了各产品的具体要求。

<a id="uninstall"></a>

## 卸载

macOS 和 Linux：

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.sh | bash
```

Windows PowerShell：

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.ps1 | iex
```

除非确认删除，否则配置文件数据会保留。

## 链接

- [支持矩阵](../support-matrix.md)
- [安全政策](../SECURITY.md)
- [贡献指南](../CONTRIBUTING.md)
- [支持](../SUPPORT.md)
- [GitHub Releases](https://github.com/Spielewoy/multi-cli/releases)

## 许可证

[MIT](../../LICENSE)
