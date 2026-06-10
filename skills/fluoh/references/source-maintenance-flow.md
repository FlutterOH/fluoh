# Source Maintenance Flow

Use this workflow when the user asks to check a FlutterOH Source checkout,
precheck a FlutterOH/source pull request, or validate Source data after syncing
released Package repositories.

## Commands

```sh
# Local YAML/index validation only.
fluoh source check [path] --schema-only --json

# Pull request or changed-route verification.
fluoh source check <source-pr-url> --json
fluoh source check . --json

# Full Source audit.
fluoh source check . --all --json
```

## Rules

- Use `--schema-only` only for local Source paths when the workflow needs pure
  YAML/index validation, such as before or after `fluoh source sync` or manual
  route edits.
- `--schema-only` does not read Git diffs, fetch SDK tags, clone Package
  repositories, verify declared releases, or touch config, snapshots, or locks.
  It reports `schemaOnly: true` in JSON and rejects PR URLs, diff options,
  release options, work-root options, and Package verification filters.
- Use normal `fluoh source check ... --json` for PR readiness, merge gates, and
  release verification. It is read-only, validates Source YAML, computes
  changed Manifest routes from Git when possible, and verifies declared Package
  release tags with `fluoh package check --package <name> --json`.
- For pull requests, pass the GitHub PR URL directly when available. The
  command clones the Source repository and fetches the PR ref through Git; it
  does not need an AI agent or GitHub API to decide the technical result.
- By default, check only Manifest files changed from `--base-ref`. If only the
  Source root `fluoh.yaml` changed, fluoh compares Manifest route names between
  the base ref and HEAD and checks only added or removed routes.
- Use `--all` for scheduled release-gate jobs.
- Use `--skip-release-checks` when a diff-aware check should validate YAML and
  changed-route selection without cloning Package repositories.
- Read JSON `schemaOnly`, `recommendation`, `errors`, `warnings`,
  `changedFiles`, `checkedManifests`, and `releaseChecks`.
- `ready` means technical checks pass, `blocked` means errors must be fixed
  before merge, and `needs-maintainer-decision` means a maintainer must decide.
- Source PR automation can publish the JSON summary as a check or comment. Do
  not approve, merge, push, or rewrite Source data automatically.
- Use `fluoh source sync [path]` only to import release records from already
  released FlutterOH Package repositories. Routing, advisory, and maintenance
  metadata remain direct Source/Manifest YAML edits.
