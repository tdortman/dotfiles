---
name: git-commit
description: Committing changes: planning commit series, writing commit messages, and applying version bumps. Invoke when committing changes, drafting or auditing a commit message, or bumping the software version. Hunk staging and splitting stay with the git-surgeon skill.
---

# git-commit

Turn the working tree into a series of atomic commits, then bump the version once for the whole series.

## 1. Plan the series

Use the `git-surgeon` skill for every step it covers: inspection, staging, splitting, validation, commit preparation. Use raw Git only when git-surgeon has no matching operation, or the prompt fixes the exact command format.

Inspect the full working tree with git-surgeon: changed files, hunks, lines, untracked files, dependencies between changes, safe staging boundaries.

Group changes by intent, not by file or diff chunk. Each commit holds one coherent reason for change: the smallest group that still keeps a working state. Unrelated edits go in separate commits.

For each planned commit, name the project problem, constraint, bug, design pressure, or user-facing need that justifies it. That need is the raw material for the commit body.

Done when every tracked and untracked change belongs to exactly one planned commit, and each commit has a stated need.

## 2. Write each message

Every rule applies to every commit message in the series.

### Shape

- One `-m` flag per `git commit`: one multi-line message argument, never stacked `-m` flags.
- Wrap the message argument in single quotes, not double quotes. Escape an apostrophe as `'\''`; avoid apostrophes otherwise.
- Title: semantic prefix, present tense, British English, 50 characters or fewer.
- One blank line between title and body.
- Body lines: 70 characters or fewer.
- No line starts with `#`. No emojis, em dashes, or semicolons.
- Wrap code symbols in `backticks`.
- British spelling and wording (`optimise`, `favour`, `colour`, `behaviour`).

### Rationale

The body explains why the repository needs the change, from the project's perspective. Keep it to the most important context. It usually answers:

- What project problem, limitation, or design pressure made the change necessary?
- Why is this approach appropriate for the codebase?
- What behaviour, API, workflow, or future change does this enable?
- What compatibility or migration constraint matters to future maintainers?

For a mechanical change, state the non-mechanical reason: preparing for an API split, removing duplicated state, enabling later validation, syncing generated artefacts.

Vague praise such as "improves maintainability" or "cleans up the code" stays only when followed by the specific reason it matters in this project.

Write the repository story only. The body never describes the agent's workflow, commit planning, series splitting, or validation. Process phrases such as "this stays one commit", "this was split", "validated earlier", "the workspace would not compile otherwise", "tested in a temporary worktree", and "validation checks" belong in the final response, not the message. A compile-time constraint may appear only as a real architectural reason, not as a splitting justification.

If the reason is unclear after reading the diff, check the session history under `$HOME/.omp/agent/sessions` before writing. Never invent rationale: if it stays unclear, write the observable reason only.

Bad body:

    "Updates parser handling and refactors helpers."

Good body:

    "The parser now accepts shared input paths from multiple call sites, so
    the normalisation step needs to live behind a single helper. Keeping the
    helper inside the parser avoids duplicating path handling before later
    callers are added."

## 3. Create and audit

Create the commits in the planned order.

When the series is complete, audit every message with `git-surgeon` or Git history inspection: title length, body line length, semantic prefix, British English, quoting, formatting. Fix any message that fails.

Done when every planned commit exists and every message passes every rule in step 2.

## 4. Version bump

Assess versioning once for the complete series, from the highest-impact change anywhere in it:

- Breaking changes outrank added functionality.
- Added functionality outranks bug fixes.
- One bump for the series: never accumulate bumps per commit, never bump twice.

Skip the bump when the series holds only internal changes that do not add, remove, change, or fix functionality, unless the project's versioning policy requires a bump.

### Selection

- Below `1.0.0`: minor for breaking changes or new functionality; patch for backwards-compatible bug fixes only. Reset patch to zero on a minor bump. `0.9.7` plus a feature becomes `0.10.0`.
- At or above `1.0.0`: major for breaking changes or removals; minor for backwards-compatible additions; patch for bug fixes. Reset less significant components to zero on a bump.

Components are not limited to single digits: `0.10.0`, `0.27.4`, `0.100.0` are valid. Never promote a pre-`1.0.0` codebase to `1.0.0` automatically: that transition needs an explicit user request.

### Apply

Find every place in the codebase that sets the software version. Update all of them together with exactly one bump.

Put the bump in a dedicated version commit at the end of the series when the project's release workflow has one; otherwise fold it into the final version-relevant commit.

Done when the series carries exactly one bump across every version location, or a justified none.
