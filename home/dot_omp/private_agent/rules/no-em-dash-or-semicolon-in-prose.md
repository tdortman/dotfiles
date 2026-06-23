---
name: no-em-dash-or-semicolon-in-prose
description: "Never use em-dashes or semicolons in code comments or formal prose (all languages)"
condition: "[\\u2014]"
scope: ["tool:edit(*)", "tool:write(*)"]
---

Never use em-dashes (—) in code comments or formal prose. Use a colon, comma, period, or break into two sentences instead. This rule applies to every programming language, not just Rust. Semicolons are also forbidden in prose and comments: rewrite comment lines as full sentences ending with a period. The regex above only auto-enforces the em-dash ban because semicolons are valid code statement terminators (Rust `;`, JS `;`, C `;`, etc.) and the tool-arg stream does not distinguish code from comments well enough to flag comment semicolons without false positives. Be diligent about avoiding `;` in comments and prose anyway.
