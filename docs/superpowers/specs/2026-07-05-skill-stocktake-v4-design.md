# Skill Stocktake v4 Design

## Goal

Make Skill Stocktake safe and usable for Codex users on Windows, macOS, and Linux while preserving existing audit history and Windows entrypoints.

## Architecture

The v4 engine is a dependency-free Python 3.10+ package invoked with `python -m skill_stocktake`. Modules separate CLI handling, discovery, fingerprints, usage, security screening, state migration/locking, redaction, and reporting. Existing PowerShell entrypoints forward to Python for one major release.

## Safety and privacy

- Session history is never read unless `--include-usage` is supplied.
- Reports redact canonical local roots; state retains paths for stable identity.
- External symlinks are excluded unless their target is covered by `--allow-symlink-root`.
- Static screening reads bounded text resources and never executes audited code or performs network requests.
- Work artifacts are scoped to `.skill-stocktake/` and are not replaced without `--force`.
- Security risk is reported separately from lifecycle quality verdicts.

## Compatibility

Schema v4 preserves logical IDs, bundle/context hashes, `last_completed`, and `active_run`. Schema-v3 migration creates a rollback backup and adds privacy/security fields without discarding verdict history. PowerShell wrappers remain available but deprecated until v5.

## Verification

CI runs Python 3.10 and the current stable Python on Windows, macOS, and Ubuntu. Windows also runs all legacy PowerShell contracts. Acceptance requires isolated fixtures, migration rollback, path redaction, opt-in usage, symlink containment, scoped writes, bounded security screening, official Codex skill validation, and zero runtime dependencies.
