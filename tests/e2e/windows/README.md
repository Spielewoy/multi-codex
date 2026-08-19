# Real-world E2E harness (Windows)

A user-like end-to-end test harness for multi-cli that runs against the
**actually installed** CLI tools on this machine. No mocks, no fixture
adapters, no fixture binaries: every profile is created and every launch goes
through the real `multi-cli.ps1` in a child `powershell.exe` process, against
the real vendor binaries found by the real adapter manifests.

## Run it

```bat
tests\e2e\windows\Invoke-RealWorldE2E.bat
```

or with parameters:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/e2e/windows/Invoke-RealWorldE2E.ps1 `
    -Tool claude-cli,codex,gemini-cli,commandcode,cursor-cli,copilot-cli,kimi-cli,grok-cli `
    -EvidenceDir "$env:TEMP\multi-cli-realworld-evidence"
```

Exit code `0` = every executed tool passed (explicit skips allowed), `1` = at
least one assertion failed. A sanitized evidence JSON is written to
`<EvidenceDir>\realworld-evidence.json` (default
`%TEMP%\multi-cli-realworld-evidence`).

The opt-in Pester suite `tests/RealWorldE2E.Tests.ps1` runs the harness for
kimi-cli, claude-cli, codex, gemini-cli, and commandcode, then asserts the
evidence shows every named assertion passed or an explicit recorded SKIP
with a reason. `tests/run-pester.ps1` excludes it from default discovery so a
host with no vendor binaries cannot satisfy required CI through skips. Run it
explicitly with `-Path RealWorldE2E.Tests.ps1`. Cursor CLI, Copilot CLI, and
Grok CLI are covered by the harness itself and record an explicit SKIP when
their binary is absent. Expect ~10-15 minutes for the Pester run: it performs
real binary launches. The suite removes its own evidence directory, harness
log, and (via the harness) the sandbox.

## What it does

Per schema-v2 `accountOverlay` adapter, dispatched by the adapter's **real**
`account.mechanism` (read from `adapter.json` at run time):

### `fileOverlay`: claude-cli, codex, gemini-cli, commandcode

1. Seed the tool's real shared normal-state root **under the test home**
   (a session/history file from `sessionPaths` + a config file from
   `sharedPaths`) *before* building profiles.
2. Create `account-a` and `account-b` via real `multi-cli new`.
3. Launch the real binary with the adapter's `versionCommand` via real
   `multi-cli launch`; assert exit code 0 and that the version output
   contains the direct binary's version output (proves the real binary ran
   under the overlay).
4. Assert the profile's `auth/` credential files are profile-local, not
   links, and **empty**, while the seeded shared/session content is visible
   through both profiles' `.runtime` and intact at the shared root.
5. Assert `.runtime` holds junctions (directories) and hardlinks (files)
   whose targets point into the shared root (credentials point into the
   profile's own `auth/`).
6. Write a session line through profile A's runtime; assert it is visible
   through profile B's runtime and at the shared root (shared conversations).
7. `doctor --deep` after clean launches: no unexpected files. Then plant
   `.runtime\rogue-e2e.txt`, assert doctor flags it, remove it, assert doctor
   is clean again.

### `processSecret`: cursor-cli, copilot-cli, kimi-cli, grok-cli

1. Store per-profile dummy tokens (`dummy-token-account-a`,
   `dummy-token-account-b`) through the same real OS credential-store module
   and target derivation used by `multi-cli auth set`. Redirected stdin behavior
   is covered separately by the launcher integration suite. `auth status`,
   `auth clear`, and all launches here are the real commands.
2. Assert real `auth status` reports the credential present.
3. Launch through a generated `.cmd` shim (passed as
   `MULTICLI_OVERRIDE_BINARY`) that writes the secret env var
   (`CURSOR_API_KEY` / `COPILOT_GITHUB_TOKEN` / `KIMI_MODEL_API_KEY` /
   `XAI_API_KEY`) to a capture file and then `exec`s the real binary with the
   version command. Assert the captured value equals the profile's dummy
   token and that the two profiles receive **different** values.
4. Assert shared normal state survives both launches. Cursor's
   `cli-config.json` is seeded with valid non-default settings and checked
   semantically because Cursor normalizes the JSON; the other adapters retain
   exact-content checks.
5. Real `auth clear` both profiles; assert a subsequent launch fails
   non-zero with the "no stored credential / auth set" hint.

## Safety model

* Sandbox root `%TEMP%\mcli_realworld` holds `home` (a dedicated test
  USERPROFILE. The operator's real profile is **never** redirected or
  written), `profiles` (MULTICLI_HOME), `tmp`, `shims`, `captures`.
* Every child process gets `USERPROFILE`/`HOME`/`APPDATA`/`LOCALAPPDATA`/
  `TEMP` redirected under the sandbox; a probe child proves it and the
  result is recorded as the `child-env-sandboxed` safety assertion.
* Child `PATH` is pre-seeded with the sandbox alias dir so `multi-cli new`
  never appends to the registry User PATH; the registry User PATH is
  snapshotted before/after. An added entry referencing the sandbox is a hard
  failure; churn caused by other processes on a live workstation (this repo's
  own legacy Pester fixtures append fixture alias dirs to the User PATH) is
  recorded as a note instead.
* Real-home marker roots (`.kimi-code`, `.codex`, `.gemini`, `.commandcode`,
  `.copilot`, `.grok`, `MultiCliProfiles`) are snapshotted (file list +
  size + mtime hash) before/after and asserted unchanged, with the differing
  root names reported on failure. `.claude` and `.claude.json` are excluded
  because this harness may run inside a Claude Code session that
  legitimately writes its own state there. Note: actively using one of the
  vendor CLIs *during* a harness run legitimately trips this assertion.
* All Credential Manager targets written (`multi-cli/<tool>/<profileId>/
  <var>`) are removed and verified absent in `finally`, including a sweep
  derived from sandbox profile metadata (covers crashed runs).
* The sandbox is removed in `finally` (junction-safe deletion that never
  traverses a reparse point). `-KeepSandbox` keeps it for debugging.
* Never opens browsers or logins and never sends prompts that consume quota.
  the only thing ever passed to a real binary is the adapter's
  `versionCommand`.

## Evidence

`realworld-evidence.json` contains: host OS/PS versions, per-tool
`status` (`pass`/`skip`/`fail`), `skipReason`, `mechanism`,
`binaryVersion`, and the named `assertions` with pass/fail and short
details; safety assertions; harness notes. Before writing, all sandbox,
`%TEMP%`, and user-profile paths are replaced by tokens and the JSON is
secret-scanned (tokens, bearer strings, `sk-*`, even the dummy token values
are excluded. Token assertions compare in memory and record only the
boolean).

## Known real-world findings recorded by this harness

* **codex** (`0.144.1`): every launch (even `--version`) writes apply-patch
  helper files `tmp/arg0/codex-arg0<random>/{.lock,applypatch.bat,
  apply_patch.bat}` into the runtime root, which `doctor --deep` flags as
  undeclared runtime files. Recorded via the vendor-transient allowlist;
  any *other* unexpected file still fails the assertion.
* **gemini-cli** (`0.42.0`): every launch leaves a transient
  `.gemini/projects.json.<guid>.tmp` under the runtime root, also flagged
  by `doctor --deep`. Allowlisted the same way (the allowlist is applied as
  a union because every `doctor` run scans the whole shared MULTICLI_HOME,
  including earlier tools' profiles).
* **codex/gemini home discovery**: outside an overlay launch, these tools
  locate the home directory via the Windows Known Folder API, not
  `USERPROFILE`. A bare direct run therefore writes into the operator's
  real `~/.codex` / `~/.gemini` even with `USERPROFILE` redirected. The
  harness's direct control runs (used for the version-match baseline) point
  the adapter's isolation env vars (`CODEX_HOME`, `GEMINI_CLI_HOME`, ...)
  at a sandbox scratch dir so nothing escapes the sandbox.
