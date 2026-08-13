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
