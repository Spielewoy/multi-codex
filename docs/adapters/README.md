# AI tool guides

Multi-CLI supports 17 AI tools. Each guide covers installation, account isolation, shared state, limitations, and platform support. The manifest beside each tool directory is the runtime source of truth.

| AI tool | Product | Type | Account boundary | Manifest |
|---|---|---|---|---|
| [`agy-cli`](agy-cli.md) | Antigravity CLI (agy) | CLI | OS user | [JSON](../../ai-tools/agy-cli/adapter.json) |
| [`antigravity`](antigravity.md) | Google Antigravity IDE | IDE | OS user | [JSON](../../ai-tools/antigravity/adapter.json) |
| [`claude-cli`](claude-cli.md) | Claude Code | CLI | File overlay | [JSON](../../ai-tools/claude-cli/adapter.json) |
| [`codex`](codex.md) | OpenAI Codex CLI | CLI | File overlay | [JSON](../../ai-tools/codex/adapter.json) |
| [`codex-gui`](codex-gui.md) | Codex Desktop App | GUI | OS user | [JSON](../../ai-tools/codex-gui/adapter.json) |
| [`commandcode`](commandcode.md) | Command Code | CLI | File overlay | [JSON](../../ai-tools/commandcode/adapter.json) |
| [`copilot-cli`](copilot-cli.md) | GitHub Copilot CLI | CLI | Process token | [JSON](../../ai-tools/copilot-cli/adapter.json) |
| [`copilot-vscode`](copilot-vscode.md) | GitHub Copilot in VS Code | IDE | OS user | [JSON](../../ai-tools/copilot-vscode/adapter.json) |
| [`cursor`](cursor.md) | Cursor Desktop | Desktop and CLI | Whole-root only | [JSON](../../ai-tools/cursor/adapter.json) |
| [`cursor-cli`](cursor-cli.md) | Cursor CLI | CLI | Process token | [JSON](../../ai-tools/cursor-cli/adapter.json) |
| [`gemini-cli`](gemini-cli.md) | Gemini CLI | CLI | File overlay | [JSON](../../ai-tools/gemini-cli/adapter.json) |
| [`grok-cli`](grok-cli.md) | Grok Build CLI | CLI | Process token | [JSON](../../ai-tools/grok-cli/adapter.json) |
| [`kimi-cli`](kimi-cli.md) | Kimi Code CLI | CLI | Process token | [JSON](../../ai-tools/kimi-cli/adapter.json) |
| [`kiro`](kiro.md) | Kiro IDE | IDE | OS user | [JSON](../../ai-tools/kiro/adapter.json) |
| [`opencode`](opencode.md) | OpenCode | CLI | Whole-root only | [JSON](../../ai-tools/opencode/adapter.json) |
| [`windsurf`](windsurf.md) | Devin Desktop (Windsurf) | IDE | OS user | [JSON](../../ai-tools/windsurf/adapter.json) |
| [`zed`](zed.md) | Zed | IDE | OS user | [JSON](../../ai-tools/zed/adapter.json) |

See the [support matrix](../support-matrix.md) for operating-system requirements and [adapter schema](../adapter-schema.md) for manifest fields.
