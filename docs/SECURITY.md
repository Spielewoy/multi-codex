# Security

## Supported versions

| Version | Security fixes |
|---|---|
| 1.x | Yes |
| Earlier versions | No |

## Report a vulnerability

Use [GitHub Security Advisories](https://github.com/Spielewoy/multi-cli/security/advisories/new). Do not open a public issue.

Include the affected version and platform, the smallest safe reproduction, the impact, and any suggested fix. Remove real credentials, account identifiers, private paths, and raw authentication data.

The maintainer will confirm receipt, validate the report, coordinate a fix, and credit the reporter unless anonymity is requested.

## Security boundary

Multi-CLI isolates account authentication only through the mode declared by each adapter. A supported adapter does not imply that every authentication mode is isolated. Unsupported or inseparable boundaries fail closed.

Treat profile directories, credential stores, session databases, logs, screenshots, and test evidence as sensitive. Never pass credentials as command-line arguments or commit them to the repository.
