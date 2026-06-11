#!/usr/bin/env bats
# Real-execution tests for `multi-cli continue` -- session continuation between
# a tool's base (~/.codex) and a profile, or between two profiles.
#
# No mocks. Each test builds a real ~/.codex fixture tree under a scratch HOME,
# runs the real launcher, and asserts on exit code, stdout, and the file tree.

load helpers/common

setup() {
  setup_scratch
}

teardown() {
  teardown_scratch
}

# 1. base -> profile copies sessions + history.jsonl, never auth.json,
#    prints the copied count and the resume hint.
@test "continue base->profile copies sessions and history, never auth.json, prints count and resumeHint" {
  seed_codex_base
  multicli new codex/backup --no-seed >/dev/null

  run multicli continue codex base backup
  [ "$status" -eq 0 ]
  [[ "$output" == *"Copied 2 file(s), skipped 0 (same-or-newer)."* ]]
  [[ "$output" == *"Resume a copied conversation with"* ]]

  local dest="$MULTICLI_HOME/codex/backup"
  [ -f "$dest/history.jsonl" ]
  [ -f "$dest/sessions/2026/06/11/rollout-2026-06-11T10-00-00-abc-123.jsonl" ]
  # genuine session_meta survived the copy intact
  run head -1 "$dest/sessions/2026/06/11/rollout-2026-06-11T10-00-00-abc-123.jsonl"
  [[ "$output" == *'"type":"session_meta"'* ]]
  # the top-level credential is never copied
  [ ! -f "$dest/auth.json" ]
}

# 2. A nested decoy credential inside sessions/ is not copied.
@test "nested decoy credential inside sessions/ is excluded by basename blocklist" {
  seed_codex_base
  multicli new codex/backup --no-seed >/dev/null

  run multicli continue codex base backup
  [ "$status" -eq 0 ]

  local dest="$MULTICLI_HOME/codex/backup"
  [ ! -f "$dest/sessions/auth.json" ]
  # but the real rollout under sessions/ did come across
  [ -f "$dest/sessions/2026/06/11/rollout-2026-06-11T10-00-00-abc-123.jsonl" ]
}

# 3. Repeat run skips everything (mtime merge): prints skipped count, copies 0.
@test "repeat continue skips all via mtime merge and copies nothing new" {
  seed_codex_base
  multicli new codex/backup --no-seed >/dev/null
  multicli continue codex base backup >/dev/null

  run multicli continue codex base backup
  [ "$status" -eq 0 ]
  [[ "$output" == *"Copied 0 file(s), skipped 2 (same-or-newer)."* ]]
}

# 4. A newer src file is re-copied; same-or-newer dest is skipped.
@test "newer source file is re-copied while up-to-date files are skipped" {
  seed_codex_base
  multicli new codex/backup --no-seed >/dev/null
  multicli continue codex base backup >/dev/null

  # Make only history.jsonl strictly newer than the dest copy.
  sleep 1
  printf '%s\n' '{"session":"abc-123","ts":1717495300,"text":"newer turn"}' \
    >> "$CODEX_BASE/history.jsonl"

  run multicli continue codex base backup
  [ "$status" -eq 0 ]
  [[ "$output" == *"Copied 1 file(s), skipped 1 (same-or-newer)."* ]]

  run cat "$MULTICLI_HOME/codex/backup/history.jsonl"
  [[ "$output" == *"newer turn"* ]]
}

# 5. --no-merge overwrites unconditionally (no skips).
@test "--no-merge re-copies every file regardless of mtime" {
  seed_codex_base
  multicli new codex/backup --no-seed >/dev/null
  multicli continue codex base backup >/dev/null

  run multicli continue codex base backup --no-merge
  [ "$status" -eq 0 ]
  [[ "$output" == *"Copied 2 file(s), skipped 0 (same-or-newer)."* ]]
}

# 6. --dry-run prints would-copy lines and writes nothing.
@test "--dry-run announces would-copy lines and writes no files" {
  seed_codex_base
  multicli new codex/backup --no-seed >/dev/null

  run multicli continue codex base backup --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would copy"* ]]
  [[ "$output" == *"Would copy 2 file(s), skipped 0 (same-or-newer)."* ]]

  local dest="$MULTICLI_HOME/codex/backup"
  [ ! -f "$dest/history.jsonl" ]
  [ ! -e "$dest/sessions" ]
}

# 7. Non-portable tool (cursor) -> exit 1 with the adapter's reason.
@test "continue on a non-portable tool exits 1 and prints the reason" {
  multicli new cursor/personal --no-seed >/dev/null 2>&1 || true
  run multicli continue cursor base personal
  [ "$status" -eq 1 ]
  [[ "$output" == *"sessions are not portable"* ]]
  [[ "$output" == *"sqlite state databases"* ]]
}

# 8. Unknown tool -> exit 1.
@test "continue with an unknown tool exits 1" {
  run multicli continue nosuchtool base backup
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown tool 'nosuchtool'"* ]]
}

# 8b. An unrecognised --flag is rejected before any work happens.
@test "continue with an unknown option exits 1 with usage" {
  run multicli continue codex base backup --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option '--bogus'"* ]]
}

# 8c. Missing positional arguments are rejected with the usage line.
@test "continue with too few arguments exits 1 with usage" {
  run multicli continue codex base
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: multi-cli continue"* ]]
}

# 9. Missing destination profile -> exit 1, suggests `multi-cli new`.
@test "continue to a missing destination exits 1 and suggests multi-cli new" {
  seed_codex_base
  run multicli continue codex base ghost
  [ "$status" -eq 1 ]
  [[ "$output" == *"Destination endpoint 'ghost' not found"* ]]
  [[ "$output" == *"multi-cli new codex/ghost"* ]]
}

# 10. src == dest -> exit 1.
@test "continue with identical source and destination exits 1" {
  run multicli continue codex base base
  [ "$status" -eq 1 ]
  [[ "$output" == *"Source and destination must differ"* ]]
}

# 11. Empty base -> exit 0 with a friendly nothing-found message.
@test "continue from an empty base exits 0 with a nothing-to-continue message" {
  mkdir -p "$CODEX_BASE"
  multicli new codex/backup --no-seed >/dev/null

  run multicli continue codex base backup
  [ "$status" -eq 0 ]
  [[ "$output" == *"No session state found for codex/base -- nothing to continue."* ]]
}

# 12. Adapter whose session paths overlap its credentials -> abort as adapter bug.
#     Tested by sourcing the launcher and calling the function against a broken
#     adapter placed in a scratch tools dir (TOOLS_DIR override).
@test "assert_session_paths_safe aborts when a session path overlaps a credential" {
  local toolsdir="$MULTICLI_SCRATCH/tools"
  mkdir -p "$toolsdir/broken"
  cat > "$toolsdir/broken/adapter.json" <<'JSON'
{
  "id": "broken",
  "displayName": "Broken",
  "session": {
    "portable": true,
    "paths": ["sessions", "secrets/auth.json"],
    "credentials": ["secrets"],
    "resumeHint": "x"
  }
}
JSON

  run bash -c "
    set -- help
    source '$MULTICLI_BIN' >/dev/null 2>&1
    TOOLS_DIR='$toolsdir'
    assert_session_paths_safe broken
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"adapter bug"* ]]
  [[ "$output" == *"overlaps credential"* ]]
}

# 17. profile -> profile continue works (not just base -> profile).
@test "continue from one profile to another copies session state" {
  seed_codex_base
  multicli new codex/source >/dev/null   # default-seeded from base
  multicli new codex/target --no-seed >/dev/null

  run multicli continue codex source target
  [ "$status" -eq 0 ]
  [[ "$output" == *"Copied 2 file(s), skipped 0 (same-or-newer)."* ]]

  local dest="$MULTICLI_HOME/codex/target"
  [ -f "$dest/history.jsonl" ]
  [ -f "$dest/sessions/2026/06/11/rollout-2026-06-11T10-00-00-abc-123.jsonl" ]
  [ ! -f "$dest/auth.json" ]
}
