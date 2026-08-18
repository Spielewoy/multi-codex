# Release process

`release/VERSION` is the canonical release version. The Bash and PowerShell entrypoints embed the same value so installed copies never depend on repository metadata.

1. Update `release/VERSION`, `VERSION` in `multi-cli`, and `$VERSION` in `multi-cli.ps1`.
2. Update `release/NOTES.md` and the support matrix.
3. Run the complete test suite.
4. Build both archives locally.
5. Merge the release commit into `main`.
6. Create and push an annotated `vX.Y.Z` tag from that commit.

```bash
bash scripts/release-build.sh
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/release-build.ps1
```

The tag starts the release workflow. It checks all three version declarations, builds the two script distributions, creates `SHA256SUMS`, records build provenance, and publishes the existing release notes. GitHub supplies source archives automatically.
