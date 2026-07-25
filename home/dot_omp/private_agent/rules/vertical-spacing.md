---
name: vertical-spacing
description: "Vertical spacing rules"
alwaysApply: true
---

# Vertical spacing

Within a block, visually isolate any statement or declaration that spans multiple source lines.

Place one blank line before and after it, unless it is already the first or last item in the surrounding block.

Treat attached comments, documentation comments, annotations, and attributes as part of the statement. Do not separate them from the code they describe.

Apply this rule to statement-level constructs such as:

- multi-line function calls
- multi-line assignments and initialisers
- `if`, `match`, loop, and exception-handling blocks
- multi-line closures or callbacks
- local function, type, or class declarations.

Do not apply it inside a single construct, such as between arguments, fields, array elements, chained calls, conditions, or match arms.

Prefer:

```rust
let config = Config {
    host,
    port,
    timeout,
};

let client = Client::builder()
    .timeout(config.timeout)
    .build()?;

client.connect().await;
```

Avoid:

```rust
let config = Config {
    host,
    port,
    timeout,
};
let client = Client::builder()
    .timeout(config.timeout)
    .build()?;
client.connect().await;
```

When two multi-line statements are adjacent, use exactly one blank line between them.
