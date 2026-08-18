# Adapter schema v2

Schema v2 separates account credentials from ordinary tool state. The machine-readable contract is [`schema/adapter.schema.json`](../schema/adapter.schema.json). Both launchers also run semantic checks before they use a manifest.

## Required fields

- `schemaVersion: 2`
- `id`, `displayName`, `kind`
- `binary.windows`, `binary.macos`, `binary.linux`, each with at least one candidate
- `isolation.strategy: accountOverlay`
- `isolation.mode: foreground` or `detached`
- `account.mechanism`
- `normalState.root.windows`, `.macos`, `.linux`
- `normalState.sharedPaths`, `.sessionPaths`, `.unsafePaths`
- `concurrency.level`, `.singletonScope`
- `support.windows`, `.macos`, `.linux`

`normalState.filePaths` is optional. It marks shared entries that must be treated as files rather than directories. `normalState.runtimeSubdir` is optional and scopes the runtime view to a safe relative directory below the declared root.

## Account mechanisms

| Mechanism | Boundary |
|---|---|
| `fileOverlay` | Credential files stay inside the profile. Declared normal state links to the native shared root. `account.credentialFiles` must not be empty. |
| `processSecret` | A credential is injected into the child process. `account.secret.environmentVariable` is required, and launch fails until `multi-cli auth set` stores the secret. |
| `osUserCredentialStore` | Each profile uses a Multi-CLI-owned OS user because the product has a fixed credential-store identity. |
| `inseparable` | Authentication and ordinary state cannot be divided safely. `account.reason` is required, account-overlay launch fails closed, and the user must choose `--isolated`. |

## Support levels

Each platform has one level:

- `supported`: at least one isolation mode works. Use `reason` to state mode requirements.
- `unsupported`: no isolation mode works. `reason` is required.

The retired `verified` and `experimental` levels are invalid. `evidenceId` is not part of the schema.

## Paths and placeholders

Accepted placeholders:

- `{profileDir}`
- `{profileId}`
- `{authDir}`
- `{runtimeRoot}`
- `{sharedStateRoot}`
- `{realHome}`

Credential and state entries are relative to their declared root. Absolute paths, drive-qualified paths, parent traversal, and overlaps between credential, shared, session, and unsafe paths are invalid.

## Validate

```bash
bash scripts/validate-adapters.sh
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Validate-Adapters.ps1
```

Schema v1 remains available for migration and legacy profile tests. New adapters must use schema v2. See the [17 adapter guides](adapters/README.md) for complete examples.
