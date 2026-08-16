# Adapter schema v2

Schema-v2 adapters describe an account boundary separately from the tool's normal state. The canonical machine-readable definition is `schema/adapter.schema.json`; both launchers also run semantic validation.

## Required contracts

- `schemaVersion: 2`
- `id`, `displayName`, `kind` (`cli`, `ide`, `gui`, or `hybrid`)
- `binary.windows|macos|linux`
- `isolation.strategy: accountOverlay`
- `isolation.mode: foreground|detached`
- `account.mechanism`
- `normalState.root`, `sharedPaths`, `sessionPaths`, `filePaths`, `unsafePaths`
- `concurrency.level`, `singletonScope`
- `support.windows|macos|linux`
- optional `appx` with `packageName`, `applicationId`, and optional `storeProductId`; it requires `osUserCredentialStore`, detached mode, and a matching `appx:<packageName>` Windows binary

## Account mechanisms

- `fileOverlay`: declared credential files live under the profile's `auth/`; declared normal state is linked to the product's native shared root.
- `processSecret`: the product supports a higher-priority per-process credential. Launch remains fail-closed until the secret has been stored through the secure credential command.
- `osUserCredentialStore`: the product uses a fixed keychain identity and requires a multi-cli-owned OS user.
- `inseparable`: auth and ordinary state cannot be divided safely. The schema records the limitation; account-overlay launches fail closed and whole-root `--isolated` profiles carry the isolation instead.

## Support levels

`support.windows|macos|linux.level` is `supported`, `experimental`, or `unsupported`.

- `supported`: multi-cli provides account isolation on that OS through at least one mode. `reason` is optional but encouraged for mode requirements (for example, "OS-user isolation; elevated terminal required").
- `experimental`: the implementation is available, but the `reason` names the real-system verification still required. `reason` is mandatory.
- `unsupported`: no isolation mode works on that OS. `reason` is required and must say why.

The retired `verified` level and the `evidenceId` field are rejected by validation.

## Placeholders

Only these placeholders are accepted:

- `{profileDir}`
- `{profileId}`
- `{authDir}`
- `{runtimeRoot}`
- `{sharedStateRoot}`
- `{realHome}`

All state/auth paths are root-relative. Absolute paths, drive-qualified paths, parent traversal, and overlapping credential/shared/session/unsafe declarations are rejected.

## Validation

```bash
bash scripts/validate-adapters.sh
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Validate-Adapters.ps1
```

Schema-v1 manifests remain accepted for legacy profile tests and migration. New integrations must use schema v2.
