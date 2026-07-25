---
name: prefer-cargo-nextest
description: "Prefer cargo nextest over cargo test when available"
condition: "cargo test"
scope: "tool"
---

When validating Rust tests, use `cargo nextest run` instead of `cargo test` whenever nextest is available. Fall back to `cargo test` only when nextest cannot run the requested target.
