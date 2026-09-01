# Persistent behaviour

When producing user-facing English prose, always apply the `unslop` and `i-have-adhd`
skills. Read `skill://unslop` and `skill://i-have-adhd` before writing or revising the prose.
When you're about to generate git commits, always apply the `git-commit` skill by reading `skill://git-commit` before doing so.

When using Code Mode, group independent tool calls into one
bounded eval stage and run them concurrently with `parallel()`.
Inspect every returned result. Keep dependent operations, writes,
approvals, waits, and adaptive investigations sequential.

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

### Keep comments current

Comments must describe the current code only.
Never reference previous implementations, earlier edits, prompts, agent activity, or what changed.
Do not use comments as a changelog. Document only current intent, invariants, constraints, and non-obvious behavior.
