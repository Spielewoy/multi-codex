#!/usr/bin/env bats
# Real-execution tests for the hardened safety branches in the bash launcher:
# staleness repair, dest-newer / equal-size skips, adapter-bug path validation,
# nested credential-named directories, the seeding size guard, symlink skipping,
# hardlink skipping (credential-leak regression), and awkward filenames. No mocks
# -- every test drives the real launcher against
# real fixture trees built under a scratch HOME.

load helpers/common

setup() {
  setup_scratch
}

teardown() {
  teardown_scratch
}

# --- staleness: repair, skip-newer, skip-equal --------------------------------

# (a) A truncated dest with the SAME mtime but a DIFFERENT size is not current
#     and must be re-copied (repaired), restoring the full content.
@test "truncated dest with equal mtime and different size is repaired" {
  seed_codex_base
  multicli new codex/backup --no-seed >/dev/null
  multicli continue codex base backup >/dev/null

  local dst="$MULTICLI_HOME/codex/backup/history.jsonl"
  local src="$CODEX_BASE/history.jsonl"
  local full_size; full_size="$(stat -c %s "$dst")"

  # Corrupt the dest: shrink it, then force its mtime to equal the source's.
  truncate -s 3 "$dst"
  touch -d "@$(stat -c %Y "$src")" "$dst"
  [ "$(stat -c %s "$dst")" -ne "$full_size" ]
  [ "$(stat -c %Y "$dst")" -eq "$(stat -c %Y "$src")" ]

  run multicli continue codex base backup
  [ "$status" -eq 0 ]
  [[ "$output" == *"Copied 1 file(s), skipped 1 (same-or-newer)."* ]]
  # The truncated file was restored byte-for-byte from the source.
  [ "$(stat -c %s "$dst")" -eq "$full_size" ]
  run cmp -s "$src" "$dst"
  [ "$status" -eq 0 ]
}

# (b) A dest that is STRICTLY NEWER than the source is left untouched (skipped).
@test "dest strictly newer than source is skipped, never overwritten" {
  seed_codex_base
  multicli new codex/backup --no-seed >/dev/null
  multicli continue codex base backup >/dev/null

  local dst="$MULTICLI_HOME/codex/backup/history.jsonl"
  # Make the dest strictly newer AND give it distinct content so an erroneous
  # overwrite would be detectable.
  printf '%s\n' 'LOCAL-EDIT-keep-me' > "$dst"
  touch -d "@$(( $(stat -c %Y "$CODEX_BASE/history.jsonl") + 100 ))" "$dst"

  run multicli continue codex base backup
  [ "$status" -eq 0 ]
  [[ "$output" == *"Copied 0 file(s), skipped 2 (same-or-newer)."* ]]
  run cat "$dst"
  [[ "$output" == *"LOCAL-EDIT-keep-me"* ]]
}

# (b') Equal mtime AND equal size is skipped (the no-op repeat case).
@test "equal mtime and equal size is skipped" {
  seed_codex_base
  multicli new codex/backup --no-seed >/dev/null
  multicli continue codex base backup >/dev/null

  run multicli continue codex base backup
  [ "$status" -eq 0 ]
  [[ "$output" == *"Copied 0 file(s), skipped 2 (same-or-newer)."* ]]
}

# --- adapter-bug path validation (assert_relpath_safe via the safe check) ------

# (c) A session path containing a '..' component aborts as an adapter bug.
@test "session path containing .. aborts as adapter bug" {
  local toolsdir="$MULTICLI_SCRATCH/tools"
  mkdir -p "$toolsdir/dotdot"
  cat > "$toolsdir/dotdot/adapter.json" <<'JSON'
{
  "id": "dotdot",
  "displayName": "DotDot",
  "session": { "portable": true, "paths": ["../escape"], "credentials": [], "resumeHint": "x" }
}
JSON
  run bash -c "
    set -- help
    source '$MULTICLI_BIN' >/dev/null 2>&1
    TOOLS_DIR='$toolsdir'
    assert_session_paths_safe dotdot
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"adapter bug"* ]]
  [[ "$output" == *"contains '..'"* ]]
}

# (c') An absolute session path aborts as an adapter bug.
@test "absolute session path aborts as adapter bug" {
  local toolsdir="$MULTICLI_SCRATCH/tools"
  mkdir -p "$toolsdir/abs"
  cat > "$toolsdir/abs/adapter.json" <<'JSON'
{
  "id": "abs",
  "displayName": "Abs",
  "session": { "portable": true, "paths": ["/etc/passwd"], "credentials": [], "resumeHint": "x" }
}
JSON
  run bash -c "
    set -- help
    source '$MULTICLI_BIN' >/dev/null 2>&1
    TOOLS_DIR='$toolsdir'
    assert_session_paths_safe abs
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"adapter bug"* ]]
  [[ "$output" == *"is absolute"* ]]
}

# (c'') A drive-letter session path aborts as an adapter bug.
@test "drive-letter session path aborts as adapter bug" {
  local toolsdir="$MULTICLI_SCRATCH/tools"
  mkdir -p "$toolsdir/drive"
  cat > "$toolsdir/drive/adapter.json" <<'JSON'
{
  "id": "drive",
  "displayName": "Drive",
  "session": { "portable": true, "paths": ["C:/Windows"], "credentials": [], "resumeHint": "x" }
}
JSON
  run bash -c "
    set -- help
    source '$MULTICLI_BIN' >/dev/null 2>&1
    TOOLS_DIR='$toolsdir'
    assert_session_paths_safe drive
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"adapter bug"* ]]
  [[ "$output" == *"drive letter"* ]]
}

# --- per-component credential blocklist ---------------------------------------

# (d) A credential-named DIRECTORY nested anywhere in the tree blocks every file
#     under it, while a sibling directory's files are copied normally.
@test "credential-named directory nested in tree blocks its files; siblings copied" {
  seed_codex_base
  # auth.json is the codex credential name. seed_codex_base plants a decoy FILE
  # at sessions/auth.json; replace it with a credential-named DIRECTORY holding a
  # secret, plus a clean sibling file.
  rm -f "$CODEX_BASE/sessions/auth.json"
  mkdir -p "$CODEX_BASE/sessions/auth.json"
  printf '%s\n' '{"OPENAI_API_KEY":"sk-NESTED-DIR-MUST-NOT-LEAK"}' \
    > "$CODEX_BASE/sessions/auth.json/leak.json"
  mkdir -p "$CODEX_BASE/sessions/keep"
  printf '%s\n' 'safe-sibling' > "$CODEX_BASE/sessions/keep/ok.txt"

  multicli new codex/backup --no-seed >/dev/null
  run multicli continue codex base backup
  [ "$status" -eq 0 ]

  local dest="$MULTICLI_HOME/codex/backup"
  # Everything under the credential-named directory is blocked.
  [ ! -e "$dest/sessions/auth.json" ]
  [ ! -f "$dest/sessions/auth.json/leak.json" ]
  # The clean sibling came across.
  [ -f "$dest/sessions/keep/ok.txt" ]
  run cat "$dest/sessions/keep/ok.txt"
  [[ "$output" == *"safe-sibling"* ]]
}

# --- seeding size guard -------------------------------------------------------

# (e) An oversize base (> SEED_MAX_BYTES) prints the actionable skip line and
#     copies nothing during seeding.
@test "oversize base skips automatic seeding with an actionable message" {
  mkdir -p "$CODEX_BASE/sessions/2026/06/11"
  # A real >500MB session file (dd allocates it so du -sk reports its size; a
  # sparse truncate would read as 0 blocks on NTFS and not trip the guard).
  dd if=/dev/zero of="$CODEX_BASE/sessions/2026/06/11/rollout-big.jsonl" \
     bs=1M count=501 status=none

  run multicli new codex/heavy
  [ "$status" -eq 0 ]
  [[ "$output" == *"base session state is"* ]]
  [[ "$output" == *"skipped automatic copy"* ]]
  [[ "$output" == *"multi-cli continue codex base heavy"* ]]

  # Nothing was seeded.
  [ ! -e "$MULTICLI_HOME/codex/heavy/sessions" ]
}

# (e') A small (under-threshold) base prints the seeding progress line.
@test "under-threshold base prints the seeding progress line" {
  seed_codex_base
  run multicli new codex/light
  [ "$status" -eq 0 ]
  [[ "$output" == *"seeding 2 session file(s) from base"* ]]
}

# --- symlink skipping ---------------------------------------------------------

# (f) A symlink inside a session tree is never dereferenced. Requires real POSIX
#     symlinks (Developer Mode / admin); skip with a reason when unavailable.
@test "symlink inside a session tree is skipped, never dereferenced" {
  seed_codex_base
  local secret="$MULTICLI_SCRATCH/outside-secret.txt"
  printf '%s\n' 'sk-SYMLINK-TARGET-MUST-NOT-LEAK' > "$secret"
  if ! make_symlink "$secret" "$CODEX_BASE/sessions/link.json" \
     || [ ! -L "$CODEX_BASE/sessions/link.json" ]; then
    skip "host cannot create real symlinks (Developer Mode/admin or POSIX ln required)"
  fi

  multicli new codex/backup --no-seed >/dev/null
  run multicli continue codex base backup
  [ "$status" -eq 0 ]

  local dest="$MULTICLI_HOME/codex/backup"
  # The symlink was not followed and its target never copied.
  [ ! -e "$dest/sessions/link.json" ]
  if [ -f "$dest/sessions/link.json" ]; then
    run cat "$dest/sessions/link.json"
    [[ "$output" != *"MUST-NOT-LEAK"* ]]
  fi
}

# (f') copy_session_entry skips a symlinked top-level entry directly (unit-level
#     guard that does not depend on real symlink creation in a deep tree).
@test "copy_session_entry returns early for a symlinked source entry" {
  if ! make_symlink /nonexistent-target "$MULTICLI_SCRATCH/maybe-link" \
     || [ ! -L "$MULTICLI_SCRATCH/maybe-link" ]; then
    skip "host cannot create real symlinks (Developer Mode/admin or POSIX ln required)"
  fi
  run bash -c "
    set -- help
    source '$MULTICLI_BIN' >/dev/null 2>&1
    COPIED=0; SKIPPED=0
    copy_session_entry '$MULTICLI_SCRATCH/maybe-link' '$MULTICLI_SCRATCH/dst' false false rel
    echo \"COPIED=\$COPIED SKIPPED=\$SKIPPED\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"COPIED=0 SKIPPED=0"* ]]
  [ ! -e "$MULTICLI_SCRATCH/dst" ]
}

# --- hardlink credential-leak regression --------------------------------------

# (h) A HARDLINK inside the session tree pointing at the base credential file is
#     skipped (nlink > 1), so its credential bytes never reach the destination.
#     Hardlinks need no admin on NTFS same-volume, so this test really runs.
@test "hardlink to a credential inside the session tree is skipped, never copied" {
  seed_codex_base
  local marker; marker="sk-HARDLINK-REGRESSION-$RANDOM$RANDOM"
  printf '%s\n' "{\"OPENAI_API_KEY\":\"$marker\"}" > "$CODEX_BASE/auth.json"

  # Hardlink a session-tree file (innocent.jsonl) onto the base auth.json. POSIX
  # hosts use `ln`; Windows hosts fall back to fsutil / mklink /H. Skip only if
  # the host refuses every mechanism.
  local link="$CODEX_BASE/sessions/2026/06/11/innocent.jsonl"
  local target="$CODEX_BASE/auth.json"
  make_hardlink "$target" "$link" || true
  if [ ! -f "$link" ] || [ "$(test_file_nlink "$link")" -lt 2 ]; then
    skip "host refused hardlink creation (ln / fsutil / mklink /H all failed)"
  fi
  # Precondition: the link really shares bytes with the credential.
  run cmp -s "$link" "$target"
  [ "$status" -eq 0 ]

  multicli new codex/backup --no-seed >/dev/null
  run multicli continue codex base backup
  [ "$status" -eq 0 ]
  # Only the 2 legitimate session files (rollout + history.jsonl) were copied.
  [[ "$output" == *"Copied 2 file(s), skipped 0 (same-or-newer)."* ]]

  local dest="$MULTICLI_HOME/codex/backup"
  # The legitimate session state arrived.
  [ -f "$dest/sessions/2026/06/11/rollout-2026-06-11T10-00-00-abc-123.jsonl" ]
  [ -f "$dest/history.jsonl" ]
  # The hardlink itself never materialized in the destination.
  [ ! -e "$dest/sessions/2026/06/11/innocent.jsonl" ]
  # No file anywhere under dest carries the credential marker (exactly 0 matches).
  local hits; hits="$(grep -rl "$marker" "$dest" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$hits" -eq 0 ]
}

# --- awkward filenames --------------------------------------------------------

# (g) A filename containing spaces copies correctly (find -print0 / read -d '').
@test "filename containing spaces copies correctly" {
  seed_codex_base
  printf '%s\n' '{"type":"session_meta"}' \
    > "$CODEX_BASE/sessions/2026/06/11/rollout with spaces.jsonl"

  multicli new codex/backup --no-seed >/dev/null
  run multicli continue codex base backup
  [ "$status" -eq 0 ]

  [ -f "$MULTICLI_HOME/codex/backup/sessions/2026/06/11/rollout with spaces.jsonl" ]
}

# (g') A filename containing a newline copies correctly (NUL-delimited loop).
@test "filename containing a newline copies correctly" {
  seed_codex_base
  local nl; nl="$(printf 'rollout\nnewline.jsonl')"
  if ! printf '%s\n' '{"type":"session_meta"}' \
       > "$CODEX_BASE/sessions/2026/06/11/$nl" 2>/dev/null \
     || [ ! -f "$CODEX_BASE/sessions/2026/06/11/$nl" ]; then
    skip "host filesystem cannot create newline filenames"
  fi

  multicli new codex/backup --no-seed >/dev/null
  run multicli continue codex base backup
  [ "$status" -eq 0 ]

  [ -f "$MULTICLI_HOME/codex/backup/sessions/2026/06/11/$nl" ]
}
