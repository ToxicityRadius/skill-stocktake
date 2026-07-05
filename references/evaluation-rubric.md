# Skill Stocktake Evaluation Rubric

## Contents

1. Evidence order
2. Evaluation dimensions
3. Verdict rules
4. Confidence rules
5. Freshness windows
6. Dependency and retirement safeguards
7. Evaluation record contract
8. Run-state contract
9. Report contract

## Evidence order

Prefer evidence in this order:

1. Current local files, executable behavior, and deterministic tests.
2. Applicable global and project instructions and configuration hashes.
3. Primary product documentation, source repositories, specifications, or release notes.
4. Observed usage and reverse-reference metadata.
5. Clearly labeled inference.

Never substitute usage frequency for quality evidence. Never retain session content, command arguments, secrets, or credentials in results.

Use these evidence types:

- `file`: exact local path plus relevant fact.
- `test`: command or fixture plus observed result.
- `runtime`: installed version or live behavior.
- `primary_source`: direct URL, publication date, and checked claim.
- `usage`: reads, unique sessions, time window, and availability.
- `dependency`: referencing path and relationship.
- `collision`: name, mirror, or bundle identity evidence.
- `uncertainty`: blocked or incomplete check.

For every `concern`, `fail`, or `unknown` dimension, set `dimension` on at least one evidence entry to that dimension name, or set `dimensions` to an array containing it. Keep evidence details concise and never copy secret-bearing source text.

## Evaluation dimensions

Rate every dimension `pass`, `concern`, `fail`, or `unknown`. Attach at least one evidence entry to each concern, failure, or unknown.

### Trigger accuracy

Check whether the frontmatter name and description cause activation for the intended requests without claiming unrelated work. Confirm that the description states triggering conditions rather than acting as a shortcut summary of the workflow.

### Actionability

Check whether a fresh agent can execute the workflow from the instructions. Verify commands, parameters, paths, prerequisites, approval boundaries, and failure handling. Treat examples that depend on unset interactive variables as failures.

### Integrity

Check frontmatter validity, referenced resources, executable syntax, bundled scripts, assets, templates, and generated metadata. Run safe focused tests. A missing required resource is a failure.

### Scope and concision

Check whether content is focused, non-repetitive, and progressively disclosed. Flag narrative history, duplicated reference material, unrelated cleanup rules, and context-heavy explanations that do not change execution.

### Uniqueness and overlap

Compare names, triggers, workflow responsibilities, bundle hashes, compatibility mirrors, and replacement coverage. Exact mirrors are one logical skill. Similar keywords alone do not establish mergeability.

### Currency

Identify version-sensitive commands, APIs, libraries, policies, and platform assumptions. Verify only the claims that can materially change the verdict. Record checked versions, primary sources, dates, and unresolved claims.

### Dependency and safety

Inspect reverse references, agent prompts, applicable instructions, configuration, scripts, and plugin metadata. Check secret handling, destructive actions, external writes, approval gates, and read-only claims.

### Maintainability

Check deterministic helpers, test coverage, schema versioning, error diagnostics, cross-version assumptions, generated state separation, and whether maintainers can update the skill without hidden coupling.

### Usefulness

Consider whether the skill solves a recurring, non-obvious problem better than general instructions. Use reads and unique sessions only as supporting context. Record `unknown` when history is unavailable.

## Verdict rules

Assign exactly one verdict.

### Keep

Use when the skill is accurate, actionable, sufficiently distinct, and has no material unresolved failure. Minor stylistic preferences do not justify Improve.

### Improve

Use when the skill remains useful and fundamentally correct but needs a concrete local quality change. Name the exact change, expected benefit, and verification method.

### Update

Use when a technical claim, command, API, dependency, policy, or platform assumption is stale or incorrect. Identify the stale fact and cite the primary evidence used to verify it.

### Merge into `<skill>`

Use only when another skill covers the same triggering conditions and workflow substantially enough that separate maintenance is cost-asymmetric. Identify the target, unique material to preserve, reverse references, migration impact, and verification needed after consolidation.

### Retire

Use only when the skill is materially defective, redundant without unique value, unsafe, or more costly than its demonstrated benefit. Identify replacement coverage, reverse references, removal impact, and recovery path.

Do not assign Merge or Retire solely from identical names, low usage, age, style, or keyword similarity.

## Confidence rules

### High

Require all verdict-critical files to be readable, relevant helpers to be tested, important currency claims to be verified, and dependencies to be known. Permit no unresolved uncertainty capable of changing the verdict.

High confidence cannot contain an `unknown` dimension or a non-empty `uncertainties` list.

### Medium

Use when evidence is strong but a non-critical check is unavailable, managed activation is inferred, or external verification has a limited gap that is unlikely to change the verdict.

### Low

Use when unreadable resources, ambiguous activation, missing history, unverified currency, or unknown dependencies could materially change the verdict.

Merge and Retire cannot have high confidence when dependency analysis is incomplete. Retire with low confidence is a research proposal, not an action recommendation.

## Freshness windows

Set `review_expires_at` from the most volatile verdict-critical claim:

- 30 days: hosted APIs, product behavior, platform policies, active plugin selection, or frequently changing CLI flags.
- 90 days: libraries, frameworks, deployment products, or versioned integrations.
- 180 days: local procedural workflows and stable tooling instructions.
- 365 days: conceptual or format guidance with no material version-sensitive claim.

Use a shorter window when a source announces an upcoming change. A changed bundle, context fingerprint, dependency set, or prior low confidence always overrides the window and schedules review.

## Dependency and retirement safeguards

Before Merge or Retire:

1. Search applicable `AGENTS.md`, agent metadata, configuration, scripts, documentation, and other skills for literal references.
2. Distinguish compatibility mirrors from independent consumers.
3. Confirm the replacement covers triggers, workflow, bundled tools, safety rules, and output contracts.
4. State which files would change and how to roll back.
5. Require explicit user approval before any mutation.

Managed/plugin skills are read-only audit subjects. Recommend upstream updates or local replacement strategies; never edit cached managed bundles.

## Evaluation record contract

Store each record under its `logical_id`:

```json
{
  "logical_id": "s-example",
  "logical_name": "example",
  "bundle_sha256": "...",
  "context_sha256": "...",
  "verdict": "Improve",
  "confidence": "high",
  "reason": "The workflow is useful, but its interactive command uses an unset variable.",
  "dimensions": {
    "trigger_accuracy": "pass",
    "actionability": "fail",
    "integrity": "pass",
    "scope_concision": "pass",
    "uniqueness_overlap": "pass",
    "currency": "pass",
    "dependency_safety": "pass",
    "maintainability": "concern",
    "usefulness": "pass"
  },
  "evidence": [
    {
      "type": "test",
      "dimensions": ["actionability", "maintainability"],
      "location": "SKILL.md command example",
      "detail": "$PSScriptRoot was unset in an interactive PowerShell process."
    }
  ],
  "reviewed_resources": ["SKILL.md", "scripts/example.ps1"],
  "uncertainties": [],
  "proposal": {
    "change": "Resolve the skill directory explicitly before invoking scripts.",
    "verification": "Run the documented command in a clean PowerShell process."
  },
  "dependencies": [],
  "replacement": null,
  "removal_impact": null,
  "reviewed_at": "2026-07-01T00:00:00Z",
  "review_expires_at": "2026-12-28T00:00:00Z"
}
```

Use `proposal: null` for Keep. Every other verdict requires a proposal with non-empty `change` and `verification` fields. For Update, include the stale claim and checked primary source. For Merge and Retire, populate `dependencies`, `replacement`, and `removal_impact`.

## Run-state contract

Use schema version 3 with stable logical IDs, separate completed and active generations, and content hashes used only for change detection. A bundle update must retain the logical ID and appear in `changed`; it must not appear as a removed-plus-added skill.

```json
{
  "schema_version": 3,
  "project_root": "C:\\project",
  "last_completed": null,
  "active_run": {
    "run_id": "uuid",
    "mode": "full",
    "status": "in_progress",
    "started_at": "2026-07-01T00:00:00Z",
    "updated_at": "2026-07-01T00:00:00Z",
    "inventory_sha256": "...",
    "context_sha256": "...",
    "pending_ids": ["s-example"],
    "evaluated_ids": [],
    "removed_ids": [],
    "diagnostics": [],
    "skills": {}
  }
}
```

Remove an ID from `pending_ids` when adding it to `evaluated_ids`. Preserve the same `run_id` for resume. Set `status` to `completed` only when pending is empty and every evaluated ID has a valid record. Full completion replaces the prior generation; quick or resume completion carries forward valid unchanged records and drops `removed_ids`.

Schema version 2 state is not silently reused. Start a full schema-version-3 run and replace the incompatible state only through the explicit replacement flag.

Only the parent evaluator writes state. Never merge parallel state files manually.

## Report contract

Start with coverage and diagnostics. Separate active, disabled, excluded, missing, unreadable, and ambiguously active roots. State whether activation was runtime-confirmed, configuration-confirmed, remote-record-confirmed, or inferred, and whether usage history was scanned. Summarize verdict and confidence counts.

Sort results by:

1. Retire and Merge proposals.
2. Update and Improve proposals.
3. Low-confidence or blocked evaluations.
4. Keep results.

Use a complete table with logical name, source, ownership, seven-day unique sessions, verdict, confidence, and concise reason. Follow it with evidence-backed proposals and a separate uncertainty section. Never describe a partial scan as complete.
