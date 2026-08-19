#!/usr/bin/env bats

load helpers/common

setup() {
  setup_scratch
  export USERPROFILE="$HOME"
  export APPDATA="$HOME/AppData/Roaming"
  export LOCALAPPDATA="$HOME/AppData/Local"
  mkdir -p "$MULTICLI_TOOLS_DIR/fixture"
  cat > "$MULTICLI_TOOLS_DIR/fixture/adapter.json" <<'JSON'
{
  "schemaVersion": 2,
  "id": "fixture",
  "displayName": "Fixture CLI",
  "kind": "cli",
  "binary": {
    "windows": ["fixture.exe"],
    "macos": ["fixture"],
    "linux": ["fixture"]
  },
  "isolation": {
    "strategy": "accountOverlay",
    "mode": "foreground",
    "env": { "FIXTURE_HOME": "{runtimeRoot}" },
    "clearEnv": []
  },
  "account": {
    "mechanism": "fileOverlay",
    "credentialFiles": ["auth.json"],
    "credentialPrecedence": ["auth.json"],
    "logoutScope": "profile"
  },
  "normalState": {
    "root": {
      "windows": "%USERPROFILE%\\.fixture",
      "macos": "$HOME/.fixture",
      "linux": "$HOME/.fixture"
    },
    "sharedPaths": ["config.toml", "agents"],
    "sessionPaths": ["sessions", "history.jsonl"],
    "filePaths": ["config.toml", "history.jsonl"],
    "unsafePaths": []
  },
  "concurrency": {
    "level": "multiWriter",
    "singletonScope": "none"
  },
  "support": {
    "windows": { "level": "supported", "reason": "Fixture only." },
    "macos": { "level": "supported", "reason": "Fixture only." },
    "linux": { "level": "supported", "reason": "Fixture only." }
  },
  "install": "https://example.test/install",
  "versionCommand": ["--version"]
}
JSON
  mkdir -p "$MULTICLI_TOOLS_DIR/legacycli"
  cat > "$MULTICLI_TOOLS_DIR/legacycli/adapter.json" <<'JSON'
{"id":"legacycli","displayName":"Legacy CLI","kind":"cli","binary":{"windows":["legacy.exe"],"macos":["legacy"],"linux":["legacy"]},"isolation":{"strategy":"env","env":{"LEGACY_HOME":"{profileDir}"}},"share":{"systemHome":"$HOME/.legacy","linkable":["config.toml"],"neverLink":["auth.json"]},"session":{"portable":true,"paths":["sessions"],"credentials":["auth.json"]},"status":"legacy-test"}
JSON
}

teardown() {
  teardown_scratch
}

make_junction() {
  local target="$1" link="$2"
  if command -v cygpath >/dev/null 2>&1 && command -v powershell.exe >/dev/null 2>&1; then
    local target_win link_win
    target_win="$(cygpath -w "$target")"
    link_win="$(cygpath -w "$link")"
    powershell.exe -NoProfile -Command "New-Item -ItemType Junction -Path '$link_win' -Target '$target_win' | Out-Null" >/dev/null
  else
    ln -s "$target" "$link"
  fi
  [ -e "$link" ]
}

@test "new rejects a traversal tool id before touching paths outside MULTICLI_HOME" {
  cp "$MULTICLI_TOOLS_DIR/fixture/adapter.json" "$MULTICLI_SCRATCH/adapter.json"

  run multicli new ../victim --no-seed

  [ "$status" -eq 1 ]
  [[ "$output" == *"Tool id '..' invalid"* ]]
  [ ! -e "$MULTICLI_SCRATCH/victim" ]
}

@test "delete refuses a junctioned tool directory that resolves outside MULTICLI_HOME" {
  local outside_root="$MULTICLI_SCRATCH/outside-fixture"
  mkdir -p "$outside_root/account-a"
  printf 'outside-data\n' > "$outside_root/account-a/keep.txt"
  make_junction "$outside_root" "$MULTICLI_HOME/fixture" || skip "host cannot create a directory link"

  run bash -c 'printf "y\n" | "$1" delete fixture/account-a' _ "$MULTICLI_BIN"

  [ "$status" -eq 1 ]
  [[ "$output" == *"outside MULTICLI_HOME"* ]]
  [ -f "$outside_root/account-a/keep.txt" ]
  [ "$(tr -d '\r' < "$outside_root/account-a/keep.txt")" = "outside-data" ]
}

@test "rename refuses a junctioned tool directory that resolves outside MULTICLI_HOME" {
  local outside_root="$MULTICLI_SCRATCH/outside-fixture"
  mkdir -p "$outside_root/account-a"
  printf 'outside-data\n' > "$outside_root/account-a/keep.txt"
  make_junction "$outside_root" "$MULTICLI_HOME/fixture" || skip "host cannot create a directory link"

  run multicli rename fixture/account-a fixture/account-b

  [ "$status" -eq 1 ]
  [[ "$output" == *"outside MULTICLI_HOME"* ]]
  [ -d "$outside_root/account-a" ]
  [ ! -e "$outside_root/account-b" ]
  [ "$(tr -d '\r' < "$outside_root/account-a/keep.txt")" = "outside-data" ]
}

@test "export refuses a junctioned tool directory that resolves outside MULTICLI_HOME" {
  local outside_root="$MULTICLI_SCRATCH/outside-fixture"
  local archive="$MULTICLI_SCRATCH/escape.tar.gz"
  mkdir -p "$outside_root/account-a"
  printf 'outside-data\n' > "$outside_root/account-a/keep.txt"
  make_junction "$outside_root" "$MULTICLI_HOME/fixture" || skip "host cannot create a directory link"

  run multicli export fixture/account-a "$archive"

  [ "$status" -eq 1 ]
  [[ "$output" == *"outside MULTICLI_HOME"* ]]
  [ ! -e "$archive" ]
  [ "$(tr -d '\r' < "$outside_root/account-a/keep.txt")" = "outside-data" ]
}

@test "template save refuses legacy whole-root copies before token files can travel" {
  local legacy="$MULTICLI_HOME/fixture/legacy"
  mkdir -p "$legacy"
  printf 'model = "gpt-5"\n' > "$legacy/config.toml"
  printf '{"access_token":"tok"}\n' > "$legacy/mcp-oauth-tokens.json"
  printf '{"refresh_token":"tok"}\n' > "$legacy/a2a-oauth-tokens.json"

  run multicli template save fixture/legacy tpl

  [ "$status" -eq 1 ]
  [[ "$output" == *"legacy profile transfer is disabled"* ]]
  [[ "$output" == *"multi-cli migrate fixture/legacy"* ]]
  [ ! -e "$MULTICLI_HOME/.templates/tpl" ]
}

@test "dot-sourced cmd_template hits the legacy transfer guard directly" {
  local legacy="$MULTICLI_HOME/fixture/legacy"
  mkdir -p "$legacy"
  printf 'model = "gpt-5"\n' > "$legacy/config.toml"

  run env MULTICLI_HOME="$MULTICLI_HOME" MULTICLI_TOOLS_DIR="$MULTICLI_TOOLS_DIR" \
    bash -c 'multicli_bin="$1"; set -- help; source "$multicli_bin" >/dev/null 2>&1; cmd_template save fixture/legacy tpl' _ \
    "$MULTICLI_BIN"

  [ "$status" -eq 1 ]
  [[ "$output" == *"legacy profile transfer is disabled"* ]]
}

@test "export refuses legacy whole-root copies before token files can travel" {
  local legacy="$MULTICLI_HOME/fixture/legacy"
  local archive="$MULTICLI_SCRATCH/legacy.tar.gz"
  mkdir -p "$legacy"
  printf 'model = "gpt-5"\n' > "$legacy/config.toml"
  printf '{"access_token":"tok"}\n' > "$legacy/mcp-oauth-tokens.json"
  printf '{"refresh_token":"tok"}\n' > "$legacy/a2a-oauth-tokens.json"

  run multicli export fixture/legacy "$archive"

  [ "$status" -eq 1 ]
  [[ "$output" == *"legacy profile transfer is disabled"* ]]
  [[ "$output" == *"multi-cli migrate fixture/legacy"* ]]
  [ ! -e "$archive" ]
}

@test "dot-sourced cmd_export hits the legacy transfer guard directly" {
  local legacy="$MULTICLI_HOME/fixture/legacy"
  local archive="$MULTICLI_SCRATCH/legacy.tar.gz"
  mkdir -p "$legacy"
  printf 'model = "gpt-5"\n' > "$legacy/config.toml"

  run env MULTICLI_HOME="$MULTICLI_HOME" MULTICLI_TOOLS_DIR="$MULTICLI_TOOLS_DIR" \
    bash -c 'multicli_bin="$1"; archive="$2"; set -- help; source "$multicli_bin" >/dev/null 2>&1; cmd_export fixture/legacy "$archive"' _ \
    "$MULTICLI_BIN" "$archive"

  [ "$status" -eq 1 ]
  [[ "$output" == *"legacy profile transfer is disabled"* ]]
}

@test "new --from refuses legacy template application before old templates can recreate credentials" {
  local template_dir="$MULTICLI_HOME/.templates/tpl"
  mkdir -p "$template_dir"
  printf 'model = "gpt-5"\n' > "$template_dir/config.toml"
  printf '{"access_token":"tok"}\n' > "$template_dir/auth.json"

  run multicli new legacycli/work --from tpl

  [ "$status" -eq 1 ]
  [[ "$output" == *"legacy template application is disabled"* ]]
  [[ "$output" == *"template 'tpl'"* ]]
  [ ! -e "$MULTICLI_HOME/legacycli/work" ]
}

@test "clone refuses legacy whole-root copies before tokens can travel" {
  local source="$MULTICLI_HOME/legacycli/source"
  mkdir -p "$source"
  printf 'model = "gpt-5"\n' > "$source/config.toml"
  printf '{"access_token":"tok"}\n' > "$source/mcp-oauth-tokens.json"

  run multicli clone legacycli/source legacycli/dest

  [ "$status" -eq 1 ]
  [[ "$output" == *"legacy profile transfer is disabled"* ]]
  [[ "$output" == *"multi-cli migrate legacycli/source"* ]]
  [ ! -e "$MULTICLI_HOME/legacycli/dest" ]
}

@test "isolated clone refuses nested directory links inside allowlisted paths" {
  run multicli new fixture/source --isolated --no-seed
  [ "$status" -eq 0 ]

  local source="$MULTICLI_HOME/fixture/source"
  local outside_root="$MULTICLI_SCRATCH/outside-clone-target"
  local nested_link="$source/sessions/shared-target"
  mkdir -p "$source/sessions" "$outside_root"
  printf 'source-config\n' > "$source/config.toml"
  printf 'source-history\n' > "$source/history.jsonl"
  printf 'outside-clone-data\n' > "$outside_root/keep.txt"
  make_junction "$outside_root" "$nested_link" || skip "host cannot create a directory link"

  run multicli clone fixture/source fixture/dest

  [ "$status" -eq 1 ]
  [[ "$output" == *"reparse point"* || "$output" == *"symlink"* ]]
  [ ! -e "$MULTICLI_HOME/fixture/dest" ]
  [ ! -e "$MULTICLI_HOME/fixture/dest/sessions/shared-target" ]
  [ "$(tr -d '\r' < "$outside_root/keep.txt")" = "outside-clone-data" ]
}

@test "import refuses legacy whole-root archives before tokens can travel" {
  local archive_root="$MULTICLI_SCRATCH/legacy-archive"
  local archive="$MULTICLI_SCRATCH/legacy.zip"
  mkdir -p "$archive_root"
  printf 'model = "gpt-5"\n' > "$archive_root/config.toml"
  printf '{"access_token":"tok"}\n' > "$archive_root/auth.json"
  python3 - "$archive_root" "$archive" <<'PY'
import pathlib
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(sys.argv[2], "w") as archive:
    for path in sorted(root.iterdir()):
        archive.write(path, path.name)
PY

  run multicli import "$archive" legacycli/work

  [ "$status" -eq 1 ]
  [[ "$output" == *"legacy profile transfer is disabled"* ]]
  [[ "$output" == *"multi-cli migrate legacycli/work"* ]]
  [ ! -e "$MULTICLI_HOME/legacycli/work" ]
}
