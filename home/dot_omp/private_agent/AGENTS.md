# Agent Instructions

## Scope and precedence

Follow the nearest `AGENTS.md` that applies to the file being edited.
Instructions in more specific directories override broader instructions, except where they weaken an explicit hard prohibition.
Before editing, inspect the applicable `AGENTS.md` files, nearby implementation, relevant tests, and repository tooling.

## Change discipline

### Make minimal changes

Make the smallest coherent change that satisfies the task.
Do not refactor, rename, reformat, reorganize, or clean up unrelated code.
Do not fix unrelated issues unless they directly block the requested work. Report blocking issues instead of silently expanding scope.

### Preserve existing patterns

Match the surrounding code's structure, naming, formatting, error handling, testing style, and abstraction level.
Use an established repository pattern when one exists. Do not introduce a new abstraction or architectural pattern without a demonstrated need.

### Avoid speculative behavior

Do not add compatibility layers, fallbacks, abstractions, defensive handling, configuration options, or extension points for hypothetical requirements.
Support only behavior demonstrated by the task, existing code, tests, or documentation.

### Limit dependency changes

Do not add, replace, or upgrade dependencies without a concrete requirement.
Prefer existing project dependencies and standard-library functionality.

## Repository safety

### Avoid unfiltered Nix flake paths

Never use `path:` flake references or `type = "path"` for a directory inside a Git repository.
Do not replace Git-aware references such as `.` with `path:.`.

Use the repository’s normal Git-aware flake reference so only tracked files are included.
A `path:` reference may copy the entire directory into the Nix store, including ignored and untracked build artefacts such as `target/`.
If Git-aware evaluation is unsuitable, report the issue rather than silently using `path:`.

### Respect existing work

Assume all existing uncommitted changes belong to the user.
Do not revert, overwrite, reformat, delete, or otherwise alter unrelated working-tree changes.
Do not use destructive commands such as `git reset --hard`, `git clean`, forced checkout, or equivalent operations unless the user explicitly requests them.

### Protect repository hygiene

Do not commit or introduce secrets, credentials, tokens, local absolute paths, debug output, temporary files, build artifacts, or editor-specific state.
Do not rewrite history or push changes unless explicitly requested.

### Treat managed files correctly

Do not manually edit generated, vendored, lock, snapshot, or machine-managed files unless the task requires it.
When such files must change, use the repository's authoritative generator, formatter, or package-management command.

## Implementation rules

### Inspect before asking

Resolve questions by inspecting the repository, documentation, types, tests, configuration, and relevant history before asking the user.
Ask only when a materially important ambiguity remains and cannot be resolved from the repository.

### Preserve failure visibility

Do not suppress errors, weaken assertions, disable tests, skip validation, add blanket exception handling, or silently fall back merely to make checks pass.
Address the underlying issue or report the failure clearly.

### Keep comments current

Comments must describe the current code only.
Never reference previous implementations, earlier edits, prompts, agent activity, or what changed.
Do not use comments as a changelog. Document only current intent, invariants, constraints, and non-obvious behavior.

### Keep tests meaningful

Add or update tests when required to verify the requested behavior.
Do not change tests solely to make incorrect implementation behavior pass.
Preserve the existing test structure and assertion style.

### Update documentation selectively

Update documentation when the task changes documented behavior, public interfaces, configuration, or user-facing workflows.
Do not make unrelated documentation edits.

## Validation

Use repository-provided scripts and commands when available.
Run the narrowest relevant validation first, such as targeted tests, type checks, linters, or builds for the affected area.
Run broader validation when justified by the scope of the change.
Never claim that code builds, tests pass, or behavior is correct unless the relevant command was actually run successfully.
Do not hide validation failures. Distinguish failures caused by the change from pre-existing or environmental failures when evidence supports that distinction.

## Commit generation

Generate granular, atomic commits using the \`git-surgeon\` skill at
\`$HOME/.agents/skills/git-surgeon/SKILL.md\`.

Prefer \`git-surgeon\` commands for inspection, staging, splitting,
validation, and commit preparation. Use raw Git commands only when
\`git-surgeon\` does not provide the needed operation, or when the prompt
explicitly constrains the exact Git command format.

Do not over-split the work. Focus on the most important changes.
Each commit should represent one coherent reason for change, not just
one edited file or one mechanical diff chunk.

Each commit must leave the repository in a valid state. After any
commit, I should be able to check it out and still have a functioning
repo. Do not create commits where the build only works again after a
later commit. If a safe split is not possible, keep the change together.

After creating the commit series, verify that each commit leaves the
repository in a functioning state.

Prefer using temporary Git worktrees to test commits independently
instead of repeatedly moving the main working tree. For each commit, check
out that commit in a clean worktree and run the relevant build, tests, or
checks for the project. Always ensure temporary worktrees are removed when
testing completes, even if a test fails.

If testing every commit is too expensive, test the commits most likely to
break the build, such as commits that change APIs, move files, update
dependencies, alter build configuration, or split a larger change across
multiple commits.

Stage changes deliberately. Do not include unrelated edits in a commit.
Use the smallest commit that still preserves a working state and a clear
reason for the change.

Before creating commits, inspect the full working tree using the
\`git-surgeon\` workflow and its most appropriate granular inspection
commands. Do not fall back to broad manual Git commands when a
\`git-surgeon\` command exists for the task.

Use \`git-surgeon\` to understand changed files, hunks, lines, untracked files,
dependencies between changes, and safe staging boundaries. Build a commit
plan that groups changes by intent. For each planned commit, identify the
specific project problem, constraint, bug, design pressure, or user-facing
need that explains why the repository needs the change.
Keep agent workflow reasoning out of the commit message.

Commit bodies must give a concrete rationale. Avoid vague explanations
such as "improves maintainability", "cleans up the code", "updates logic",
or "makes things better" unless they are immediately followed by the
specific reason this matters in the project.

A good commit body should usually answer:

- What project problem, limitation, or design pressure made this change
  necessary?
- Why is this implementation approach appropriate for the codebase?
- What behaviour, API, workflow, or future change does this enable?
- What compatibility or migration constraint matters to future maintainers?

If the change is mechanical, explain the non-mechanical reason it is
needed, such as preparing for an API split, reducing duplicated state,
making later validation possible, or keeping generated artefacts in sync.

### Commit Message Constraints

For each commit message, you must strictly adhere to these rules:

- Use British English spelling and wording, for example \`optimise\`,
  \`favour\`, \`colour\`, and \`behaviour\`.
- Use present tense.
- Use a semantic commit prefix.
- Title length: Maximum 50 characters.
- Body line length: Maximum 70 characters.
- Keep an empty line between the title and body.
- Explain why the change was made, not just what changed.
- For every commit body, explain the cause or pressure behind the change,
  not merely the resulting code difference.
- Focus the body on the most important context.
- Wrap code symbols in \`backticks\`.
- Do not start any line with \`#\`.
- Do not use emojis, em dashes, or semicolons.

Commit bodies must not explain the agent's process, commit-planning
decision, or validation workflow unless that information is directly useful
to a future maintainer of the repository.

Do not write phrases such as "this stays one commit", "this was split",
"the risk is prompt drift", "validation checks", or similar process notes
in commit messages. Keep that reasoning in the final summary instead.

The commit body should explain why the repository needs the change from the
project's perspective. It should not justify why the agent chose a
particular commit boundary.

Commit messages must describe the repository change from the project's
perspective. Do not describe the agent's workflow, commit planning, series
splitting, or validation process.

Never include process phrases such as:

- "validated earlier"
- "before the series was split"
- "this commit is kept as one boundary"
- "this split is kept in one commit"
- "the workspace would not compile otherwise"
- "tested in a temporary worktree"
- "validation checks"

Keep validation details in the final response after the commits are
created, not in the commit message body.

It is acceptable to mention compile-time constraints only when they are a
real architectural reason for the change, not as a justification for how
the agent split the series.

Bad body:
"Updates parser handling and refactors helpers."

Good body:
"The parser now accepts shared input paths from multiple call sites, so the
normalisation step needs to live behind a single helper. Keeping the helper
inside the parser avoids duplicating path handling before later callers are
added."

### Shell Formatting Safety

Each \`git commit\` command must contain exactly one \`-m\` flag. Use a
single multi-line message argument instead of multiple \`-m\` flags.

Wrap the entire commit message argument in single quotes, not double
quotes. If you must use an apostrophe inside the message, escape it safely
for Bash using \`'\\''\`, for example \`don'\\''t\`. Otherwise, completely
avoid apostrophes.

If there is even a sliver of uncertainty about the reason behind a change,
check the project's session history under \`$HOME/.omp/agent/sessions\`
before writing the commit message.

Do not invent rationale. If the reason for a change is unclear after
inspecting the diff and session history, say so in the commit body using
careful wording, or keep the body limited to the observable reason.

After creating the commit series, audit the commit messages using
\`git-surgeon\`, Git history inspection, or an equivalent command. Verify
that every commit message satisfies the title length, body line length,
semantic prefix, British English, quoting, and formatting constraints. Fix
any commit message that fails the audit.

### Semantic Versioning

Assess versioning once for the complete commit series, not separately for
each commit.

If the series adds, removes, changes, or fixes functionality, find every
place in the codebase that sets the software version. Apply exactly one
version bump across the entire series and update all version locations
together.

Determine the required bump from the highest-impact change anywhere in
the series:

- Breaking changes take precedence over added functionality.
- Added functionality takes precedence over bug fixes.
- Do not combine or accumulate bumps from individual commits.
- Do not bump the version again after the aggregate bump has been applied.

Prefer a dedicated version commit at the end of the series when that
matches the project's existing release workflow. Otherwise, include the
single bump in the final commit that changes version-relevant
functionality.

Never automatically promote a pre-`1.0.0` codebase to `1.0.0`. The
transition to `1.0.0` is a deliberate project decision and must only
happen when the user explicitly requests it.

Version components are not limited to single digits. Versions such as
`0.10.0`, `0.27.4`, and `0.100.0` are valid. Do not promote a project to
`1.0.0` merely because its current minor version is `9` or greater.

When the current version is below `1.0.0`:

- Increment the minor version if the series contains incompatible API
  changes, removed functionality, other breaking changes, or new
  functionality.
- Increment the patch version if the series contains only
  backwards-compatible bug fixes.
- Reset the patch version to zero when incrementing the minor version.

For example:

- A series based on `0.3.4` that adds several features becomes `0.4.0`,
  not `0.6.0`.
- A series based on `0.3.4` that contains features and bug fixes becomes
  `0.4.0`.
- A series based on `0.3.4` that contains only bug fixes becomes `0.3.5`.
- A series based on `0.9.7` that adds functionality or makes breaking
  changes becomes `0.10.0`.
- `0.9.7` must not become `1.0.0` without an explicit user instruction.

When the current version is at least `1.0.0`:

- Increment the major version if the series contains incompatible API
  changes or removed functionality.
- Increment the minor version if the series adds backwards-compatible
  functionality and contains no breaking changes.
- Increment the patch version if the series contains only
  backwards-compatible bug fixes.
- Reset all less significant version components to zero when incrementing
  a more significant component.

Do not bump the version when the complete series contains only internal
changes that do not add, remove, change, or fix software functionality,
unless the project's established versioning policy requires a bump.
