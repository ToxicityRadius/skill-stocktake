# Contributing

Contributions should preserve the audit's read-only default, deterministic state handling, and Windows PowerShell compatibility.

1. Create a focused branch.
2. Add or update a fixture for behavior changes.
3. Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1`.
4. Validate `SKILL.md` with Codex's official `quick_validate.py` when available. On Windows, set `$env:PYTHONUTF8='1'` first.
5. Open a pull request describing behavior, compatibility impact, and verification.

Do not include real session content, credentials, private repository paths, or generated audit state in fixtures.
