#!/usr/bin/env bats
# Real-execution tests for the seeding hook in `multi-cli new`
# (seed_profile_from_base). No mocks: a real ~/.codex base is built in a
# scratch HOME and the real launcher creates profiles against it.

load helpers/common

setup() {
  setup_scratch
}

teardown() {
  teardown_scratch
}

# 13. A new plain profile default-seeds session state from base AND the
#     adapter's linkable assets (config.toml).
@test "new default-seeds session state and linkable assets from base" {
  seed_codex_base

  run multicli new codex/dev
  [ "$status" -eq 0 ]
  [[ "$output" == *"Seeded from base: session state (2 file(s))"* ]]
  [[ "$output" == *"shared asset(s)"* ]]

  local pdir="$MULTICLI_HOME/codex/dev"
  [ -f "$pdir/history.jsonl" ]
  [ -f "$pdir/sessions/2026/06/11/rollout-2026-06-11T10-00-00-abc-123.jsonl" ]
  [ -f "$pdir/config.toml" ]          # linkable asset seeded
  [ ! -f "$pdir/auth.json" ]          # credential never seeded
  [ ! -f "$pdir/sessions/auth.json" ] # nested decoy never seeded
}

# 14. new --no-seed seeds nothing.
@test "new --no-seed creates an empty profile and seeds nothing" {
  seed_codex_base

  run multicli new codex/clean --no-seed
  [ "$status" -eq 0 ]
  [[ "$output" != *"Seeded from base"* ]]

  local pdir="$MULTICLI_HOME/codex/clean"
  [ ! -f "$pdir/history.jsonl" ]
  [ ! -e "$pdir/sessions" ]
  [ ! -f "$pdir/config.toml" ]
}

# 15. new --shared seeds session state but not linkables (via the seeding hook).
@test "new --shared seeds session state but the seed hook adds no linkable assets" {
  seed_codex_base

  run multicli new codex/shr --shared
  [ "$status" -eq 0 ]
  # The seed line reports session state only -- no "shared asset(s)" from the hook.
  [[ "$output" == *"Seeded from base: session state (2 file(s))"* ]]
  [[ "$output" != *"session state (2 file(s)),"* ]]

  local pdir="$MULTICLI_HOME/codex/shr"
  [ -f "$pdir/.shared" ]
  [ -f "$pdir/history.jsonl" ]
  [ -f "$pdir/sessions/2026/06/11/rollout-2026-06-11T10-00-00-abc-123.jsonl" ]
}

# 15b. With an existing-but-empty base, the seed hook runs but finds nothing to
#      copy, so it prints no "Seeded from base" line.
@test "new against an empty base prints no seeded line" {
  mkdir -p "$CODEX_BASE"   # base exists but has no session state or linkables

  run multicli new codex/dev
  [ "$status" -eq 0 ]
  [[ "$output" != *"Seeded from base"* ]]

  local pdir="$MULTICLI_HOME/codex/dev"
  [ ! -f "$pdir/history.jsonl" ]
  [ ! -e "$pdir/sessions" ]
}

# 16. new --from <template> skips seeding entirely.
@test "new --from <template> skips base seeding" {
  seed_codex_base
  # Build a source profile and save it as a template.
  multicli new codex/src --no-seed >/dev/null
  printf '%s\n' 'from-template = true' > "$MULTICLI_HOME/codex/src/marker.toml"
  multicli template save codex/src tmpl >/dev/null

  run multicli new codex/fromtpl --from tmpl
  [ "$status" -eq 0 ]
  [[ "$output" != *"Seeded from base"* ]]

  local pdir="$MULTICLI_HOME/codex/fromtpl"
  [ -f "$pdir/marker.toml" ]          # came from the template
  [ ! -f "$pdir/history.jsonl" ]      # base seeding did not run
  [ ! -e "$pdir/sessions" ]
}
