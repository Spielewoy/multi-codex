# claude-cli: Claude Code

**Account boundary:** `fileOverlay`: the subscription credential `.credentials.json` is profile-local; everything else declared in `adapter.json` is shared normal state.

Claude Code reads its config tree from `CLAUDE_CONFIG_DIR`. The adapter points it at a per-profile runtime view where only the credential file belongs to the profile and every declared ordinary path links back to the native shared root.

## Install

```bash
npm i -g @anthropic-ai/claude-code
```

Binary discovery: `%APPDATA%\npm\claude.cmd` (Windows), `/usr/local/bin/claude` (macOS), `$HOME/.npm-global/bin/claude` (Linux), then `claude` on PATH.

## Quickstart

```bash
multi-cli new claude-cli/work
multi-cli launch claude-cli/work       # /login on first run; credentials stay profile-local
multi-cli new claude-cli/personal
multi-cli launch claude-cli/personal
```

Conversations are shared normal state, so `multi-cli continue` is not needed between schema-v2 profiles (it remains available for legacy profiles).

## Account boundary

- Profile-local credentials: `.credentials.json` (the sole entry in the declared precedence chain).
- Launch env: `CLAUDE_CONFIG_DIR={runtimeRoot}`.
- Logout scope: profile.

## Shared normal state

Shared root: `%USERPROFILE%\.claude` (Windows), `~/.claude` (macOS/Linux).

- Config: `CLAUDE.md`, `settings.json`, `keybindings.json`, `remote-settings.json`, `stats-cache.json`, `themes/`, `rules/`, `skills/`, `commands/`, `output-styles/`, `agents/`, `workflows/`, `agent-memory/`, `plugins/`.
- Sessions: `projects/`, `history.jsonl`.
- Ordinary state: `file-history/`, `plans/`, `debug/`, `paste-cache/`, `image-cache/`, `session-env/`, `tasks/`, `shell-snapshots/`, `backups/`, `feedback-bundles/`.

## Known limitations

- Do not put `ANTHROPIC_API_KEY` or other auth environment into the shared `settings.json`: it would apply to every profile at once.
- macOS subscription OAuth lives in a fixed Keychain context, so same-user profiles can overwrite each other's login. This adapter supports API-key profiles there; subscription OAuth is unsupported because this adapter does not provide a separate macOS login/Keychain session.

## Support

| Windows | macOS | Linux |
|---|---|---|
| supported (file overlay) | supported for API-key profiles only; subscription OAuth is unsupported | supported (file overlay) |
