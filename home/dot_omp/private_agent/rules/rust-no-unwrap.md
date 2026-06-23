---
name: rust-no-unwrap
description: "Never use .unwrap() in Rust — handle errors with ?, .expect(), or explicit match"
condition: "\\.unwrap\\s*\\("
scope: ["tool:edit", "tool:write"]
---

In Rust, do not call `.unwrap()`. Prefer one of:

- `?` to propagate the error with the appropriate `From`/`Into` conversion.
- `.expect("documented invariant")` only when a panic is genuinely the correct behavior and the message states the invariant the test is asserting.
- An explicit `match` / `if let Err(...)` that handles the failure case (log it, fall back, surface it to the caller, etc.).

`.unwrap()` on a `Result` or `Option` is a code smell. The only acceptable replacement is `.expect()` with a meaningful message, and even that should be reserved for tests and unreachable branches. Production code paths must propagate or handle the error.