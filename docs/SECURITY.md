# Security Policy

## Supported versions

Security fixes are provided for the current 1.x release line.

| Release line | Security updates |
|---|---|
| 1.x | Supported |
| Earlier versions | Not supported |

Upgrade to the latest available release before reporting a problem that may already be fixed.

## Report a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/Spielewoy/multi-cli/security/advisories/new). Do not open a public issue, pull request, or discussion for a suspected vulnerability.

Include as much of the following as you can safely provide:

- The affected Multi-CLI version or commit.
- The operating system, shell, AI tool, and profile mode.
- The security boundary you expected and what occurred instead.
- The prerequisites, impact, and shortest safe reproduction.
- A minimal proof of concept, suggested mitigation, or proposed fix if available.

Remove real credentials, tokens, account identifiers, private paths, authentication databases, and unrelated personal data. Attach sensitive evidence only to the private advisory.

If private vulnerability reporting is unavailable, do not publish the details. Use a public issue only to ask for a private reporting channel, without identifying the vulnerability or its impact.

## What to report

Security reports include, but are not limited to:

- Credentials or authenticated state crossing profile boundaries.
- Unexpected inheritance, storage, disclosure, or execution of secrets.
- Authentication or account isolation that fails open.
- Command injection, unsafe path handling, or unintended file access caused by Multi-CLI.
- A release artifact that does not match its published checksum or provenance.

Usage questions, unsupported configurations, and ordinary defects without a security impact belong in the public issue forms. Vulnerabilities in an AI tool or operating system that do not arise from Multi-CLI should be reported to that upstream project.

## Response and disclosure

The maintainer will use the private advisory to confirm the report, assess affected versions and impact, coordinate a fix, and plan disclosure. Additional information or validation may be requested. Reporter credit will be offered unless anonymity is requested.

Keep the report and related evidence private until a fix and advisory are published or another disclosure plan is agreed upon in the advisory. Published advisories will identify affected versions, available fixes, and mitigations when applicable.

## Security boundary

Multi-CLI isolates account authentication only through the mode declared for each supported AI tool. Support for an AI tool does not mean every sign-in method can be isolated. Unsupported or inseparable account boundaries must fail closed.

Treat profile directories, credential stores, session databases, logs, screenshots, and test evidence as sensitive. Never pass credentials as command-line arguments or commit sensitive material to the repository. Review the [support matrix](support-matrix.md) for platform-specific boundaries before relying on an isolation mode.
