---
description: Disallow Rust tuple types, use named structs instead
astCondition:
    - "type __OmpTuple = ($A, $$$REST);"
scope: "tool:edit(*.rs), tool:write(*.rs)"
---

Do not introduce Rust tuple types. Use a named `struct` with descriptive fields instead.

Do not write tuple types such as:

```rust
(A,)
(A, B)
(A, B, C)
Option<(A, B)>
Vec<(A, B)>
```

For example, do not write:

```rust
fn parse() -> (Score, Packed) {
    ...
}
```

Instead, define a named type:

```rust
struct Parsed {
    score: Score,
    packed: Packed,
}

fn parse() -> Parsed {
    ...
}
```

This applies to tuple types wherever they occur, including function return types, parameters, variable type annotations, struct fields, type aliases, and tuple types nested inside generic types.

Tuple expressions and tuple patterns are allowed when they do not require introducing a tuple type. For example, idiomatic destructuring is fine:

```rust
for (key, value) in map {
    ...
}

let (key, value) = entry;
```
