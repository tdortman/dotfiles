# Agent Instructions

## Scope and precedence

Follow the nearest `AGENTS.md` that applies to the file being edited.
Instructions in more specific directories override broader instructions, except where they weaken an explicit hard prohibition.
Before editing, inspect the applicable `AGENTS.md` files, nearby implementation, relevant tests, and repository tooling.

## Implementation rules

### Inspect before asking

Resolve questions by inspecting the repository, documentation, types, tests, configuration, and relevant history before asking the user.
Ask only when a materially important ambiguity remains and cannot be resolved from the repository.

### Preserve failure visibility

Do not suppress errors, weaken assertions, disable tests, skip validation, add blanket exception handling, or silently fall back merely to make checks pass.
Address the underlying issue or report the failure clearly.

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
