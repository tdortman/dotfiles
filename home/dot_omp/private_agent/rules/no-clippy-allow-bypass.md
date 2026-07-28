---
name: no-clippy-allow-bypass
description: "Never silence clippy lints with #allow(clippy::...); fix the underlying code instead"
condition: "#\\[allow\\(clippy::[a-z_:]+"
scope: ["tool:edit(*.rs)", "tool:write(*.rs)"]
---

Do not suppress clippy lints with `#[allow(clippy::...)]`. Rewrite the code to satisfy the lint. For FFI implicit borrows, pass `&raw const x` or `&raw mut x` instead of `&x` or `&mut x`. For unaligned cmsg writes, use `std::ptr::write_unaligned` / `read_unaligned` with a `*mut u8` target instead of casting to a stricter alignment. For size casts, use `u32::try_from(...).expect(...)` instead of `as u32`. If a clippy lint is genuinely wrong for FFI, place the `#[allow(...)]` on the narrowest statement with a one-line justifying comment, never a blanket function-level `#[allow(clippy::cast_ptr_alignment)]`.