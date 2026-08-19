# Release process

`release/VERSION` is the canonical release version. The Bash and PowerShell entrypoints embed the same value so installed copies never depend on repository metadata.

## Requirements

- Bash, PowerShell, Git, `tar`, `zip`, `unzip`, and `sha256sum`
- GitHub permission to merge the release pull request and push a version tag
- A clean feature branch with every CI job passing

1. Update `release/VERSION`, `VERSION` in `multi-cli`, and `$VERSION` in `multi-cli.ps1`.
2. Update `release/NOTES.md` and the support matrix.
3. Run the complete test suite.
4. Build both archives locally.
5. Merge the release pull request after every required check passes. Do not push directly to `main`.
6. Create and push an annotated `vX.Y.Z` tag from the merge commit.

```bash
bash release/build.sh
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File release/build.ps1
```

The tag starts the release workflow. It rejects commits outside `main`, checks all three version declarations, builds both archives, creates `SHA256SUMS`, records build provenance, and publishes the release notes. GitHub supplies source archives automatically.
