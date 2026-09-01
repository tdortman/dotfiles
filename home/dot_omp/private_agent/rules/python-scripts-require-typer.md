---
name: python-scripts-require-typer
description: "Use Typer instead of ArgumentParser in standalone Python scripts"
condition: "\\b(?:argparse\\.)?ArgumentParser\\s*\\("
scope: ["tool:write(*.py)", "tool:edit(*.py)"]
---

Standalone Python programs must use `typer`, with `Annotated` parameter types, instead of `ArgumentParser`. Follow the repository's existing Typer script conventions.
