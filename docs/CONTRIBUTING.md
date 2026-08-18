# Contributing

## Before you start

- Search existing issues and pull requests.
- Open an issue before a large behavior or adapter change.
- Report vulnerabilities through [GitHub Security Advisories](https://github.com/Spielewoy/multi-cli/security/advisories/new), never a public issue.

## Local checks

Install Git, Bash, PowerShell, and `jq`. Then run the checks that match your change:

```bash
bash scripts/validate-adapters.sh
bash tests/run-bats.sh
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Validate-Adapters.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-pester.ps1
```

Run both adapter validators when an adapter changes. Platform-specific claims need a real run on that platform.

## Pull requests

- Keep one focused change per pull request.
- Explain the user-visible behavior and list the exact checks run.
- Add tests for behavior changes and update affected docs.
- Do not commit credentials, account identifiers, local paths, profiles, raw logs, screenshots, or vendor evidence.
- Preserve fail-closed behavior around authentication and account isolation.

By contributing, you agree that your contribution is licensed under the repository's MIT License.
