# Contributing to Multi-CLI

Thank you for improving Multi-CLI. Contributions are welcome when they are focused, tested, and safe for users who rely on account isolation.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Choose the right channel

- Search [existing issues](https://github.com/Spielewoy/multi-cli/issues) before opening a new one.
- Use the repository's issue forms for reproducible bugs, focused feature requests, usage questions, and new AI tool proposals.
- Open an issue before a large behavior change or a change to an account boundary.
- Report vulnerabilities through [GitHub private vulnerability reporting](https://github.com/Spielewoy/multi-cli/security/advisories/new), not in a public issue. See the [security policy](SECURITY.md) for reporting details.

Small documentation corrections may be submitted directly as a pull request.

## Development requirements

Install only the tools needed for the part of the project you change:

- [Git](https://git-scm.com/downloads).
- [Bash 3.2 or newer](https://www.gnu.org/software/bash/) for the POSIX launcher and tests.
- [Windows PowerShell 5.1 or newer](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) for the Windows launcher and tests.
- [Pester 3.4 or newer in the 3.x series](https://www.powershellgallery.com/packages/Pester/3.4.0) for PowerShell tests.
- [Python 3.10 or newer](https://www.python.org/downloads/) for documentation validation and coverage checks.
- [`jq` 1.7.1](https://jqlang.github.io/jq/download/) for launcher and adapter validation.

The Bats runner bootstraps its pinned Bats and `jq` test dependencies when they are not already available. Coverage checks have additional requirements documented in the [testing guide](testing.md#coverage).

## Prepare a change

Fork the repository, clone your fork, and create a branch from the latest `main`:

```bash
git clone https://github.com/YOUR-USER/multi-cli.git
cd multi-cli
git remote add upstream https://github.com/Spielewoy/multi-cli.git
git fetch upstream
git switch -c concise-change-name upstream/main
```

Keep the change focused. Preserve compatibility with Bash 3.2 and Windows PowerShell 5.1. Do not weaken validation, path safety, credential handling, or fail-closed behavior to make a test pass.

For an AI tool definition, follow the [adapter schema](adapter-schema.md). Update the definition, its user guide, and the support table together. Run both adapter validators. A platform or isolation claim requires a real run on that platform.

## Test the change

Run the checks that match the files and platforms you changed.

On macOS or Linux:

```bash
bash scripts/validate-adapters.sh
bash tests/run-bats.sh
python3 scripts/validate-docs.py
```

On Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Validate-Adapters.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-pester.ps1 -CI
python scripts/validate-docs.py
```

Behavior changes need tests that fail without the change and pass with it. Changed production lines must meet the repository's 95% changed-line coverage requirement. Run the relevant coverage gate:

```bash
bash tests/coverage/run-bash-coverage.sh
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/coverage/Run-PowerShellCoverage.ps1
```

See [Testing](testing.md) for coverage dependencies and protected real-world verification. Do not submit private vendor evidence or claim platform support based only on fixtures.

## Submit a pull request

- Target `main` and keep one logical change per pull request.
- Use a clear title and explain the user-visible behavior.
- Link the related issue when one exists.
- Complete the pull request template and list the exact checks run and their results.
- Add or update tests for behavior changes and update affected documentation.
- Note platform limitations or checks you could not run.
- Do not commit credentials, tokens, account identifiers, private paths, profiles, raw logs, screenshots, generated coverage output, or vendor evidence.
- Ensure commits contain only intended files and do not include generated or editor-specific artifacts.

The maintainer may request changes before merging. A pull request is ready when required checks pass, review feedback is resolved, and documentation matches the implementation.

## Licensing

By contributing, you agree that your contribution is licensed under the repository's [MIT License](../LICENSE).
