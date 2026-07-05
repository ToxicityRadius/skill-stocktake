# Skill Stocktake v4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Windows-only engine with a privacy-safe, security-aware, cross-platform Python implementation while preserving schema-v3 history and PowerShell compatibility.

**Architecture:** A standard-library Python package owns discovery, analysis, state, and reports. Existing PowerShell commands become deprecated forwarding wrappers. Schema-v4 migration and multi-OS CI protect compatibility.

**Tech Stack:** Python 3.10+ standard library, PowerShell compatibility wrappers, `unittest`, GitHub Actions.

---

- [ ] Establish baseline and record the approved design.
- [ ] Add the Python package and stable CLI/exit-code contract test-first.
- [ ] Port discovery, configuration, fingerprints, and symlink containment.
- [ ] Add opt-in session usage and report-only path redaction.
- [ ] Add bounded, non-executing security screening.
- [ ] Add schema-v4 validation, v3 migration, locking, and atomic persistence.
- [ ] Add scoped/no-clobber artifacts and privacy-safe reporting.
- [ ] Convert PowerShell entrypoints to deprecated forwarding wrappers.
- [ ] Update documentation and multi-OS CI; verify and release v4.0.0.
