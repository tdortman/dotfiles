---
name: no-clippy-bypass
description: "Fix the underlying code that triggers a compiler or Clippy warning instead of suppressing it with `#[allow(...)]` or `#[expect(...)]`. The only acceptable suppression is `#[allow(unsafe_code)]` on actual unsafe code."
condition: "#[(allow|expect)\((dead_code|clippy::[a-zA-Z_]+)\)\]"
scope: ["tool:edit(*.rs)", "tool:write(*.rs)"]
---

Never suppress a compiler or Clippy warning with `#[allow(dead_code)]`, `#[expect(dead_code)]`, `#[allow(clippy::xxx)]`, or `#[expect(clippy::xxx)]`. The only acceptable suppression is `#[allow(unsafe_code)]` on actual unsafe code. Fix the underlying code instead:

* `dead_code` on a method/field/struct: either call it from real code or delete it. Speculative "future use" is not a justification — the compiler will tell you when you need it back.
* `dead_code` on a function arg: prefix it with `_` or remove the arg if unused.
* `clippy::map_unwrap_or` → use `.map_or(default, |x| ...)`.
* `clippy::cast_possible_wrap` on a FUSE flag or kernel type → use `.cast_signed()` (idiomatic and documents intent).
* `clippy::cast_possible_truncation` on `as u32` from a kernel-reported count → use `u32::try_from(x).expect("...")` or, when the value is guaranteed to be less than `u32::MAX`, `.cast()` (after `clippy::cast_lossless` is allowed; otherwise add `cast()`).
* `clippy::borrow_as_ptr` → use `&raw mut var`.
* `clippy::needless_pass_by_value` → take `&T` (or `impl AsRef<T>` if you also want to accept owned values).
* `clippy::items_after_statements` → move the `use` or `static` to the top of the block.
* `clippy::duration_suboptimal_units` for `Duration::from_secs(60)` → use `Duration::from_mins(1)`.
* `clippy::unused_self` → make it an associated function by dropping `&self`.
* `clippy::ptr_arg` on `&PathBuf` → take `&Path`.
* `clippy::map_unwrap_or` on `Option` → use `.map_or(default, |x| ...)`.
* `clippy::unnecessary_debug_formatting` or `clippy::uninlined_format_args` → use `{var:?}` or `{var}` inline.
* `clippy::match_same_arms` → collapse identical arms, for example `A | B => panic!("expected X")`.

If a compiler or Clippy lint appears to be genuinely wrong, do not add either `#[allow(...)]` or `#[expect(...)]`. Raise the issue with the user before shipping any suppression.