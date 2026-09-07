# Agent Instructions

## Scope and precedence

Follow the nearest `AGENTS.md` that applies to the file being edited.
Instructions in more specific directories override broader instructions, except where they weaken an explicit hard prohibition.
Before editing, inspect the applicable `AGENTS.md` files, nearby implementation, relevant tests, and repository tooling.

## Inspect before asking

Resolve questions by inspecting the repository, documentation, types, tests, configuration, and relevant history before asking the user.
Ask only when a materially important ambiguity remains and cannot be resolved from the repository.

## Preserve failure visibility

Do not suppress errors, weaken assertions, disable tests, skip validation, add blanket exception handling, or silently fall back merely to make checks pass.
Address the underlying issue or report the failure clearly.


## Persistent behaviour

The user's instructions take precedence over guidelines provided in a skill.
If explicit user instructions conflict with a skill's instructions, prioritize the user's instructions.

If at any point you can parallelize work by delegating tasks to another agent (no matter if you are the root or subagent),
you should do so using collaboration tools if it could save time or improve quality.
Messages that you send to other agents and your final answer may be read by a human, so ensure they are legible.
Always put proper spaces between words and/or numbers.

When the user's prompt indicates a request for action, such as "can you...", "I want to...", "help me..." and similar expressions, treat these as instructions to do the work and take action.
Do not stop at acknowledging capability (e.g. "Yes…"), proposing a plan, or offering to continue.
Do not settle for a partial or "helpful enough" solution that does not fully satisfy the user's task to save time, effort or tokens.
If a task requires sustained work, complete all the necessary work until the intended outcome is fulfilled.

Before asking the user clarifying questions, you should complete the work that is already authorized from context and necessary to make the proposed action concrete and reviewable.
The user should be approving a concrete, reviewable result.
For example, before deploying a change, writing to an external application, merging a PR or publishing a site, do all the required work first so that user approval is the final step.
You don't need user permission for reversible tasks, read-only actions, reviews or fixes, or anything for which authorization is provided earlier in the session or strongly implied from the task instruction.

Do not introduce unsolicited warnings, disclaimers, approval flows, or safety/compliance checklists due to hypothetical risk.

## Testing: Prefer Behavioural, Integration, and End-to-End Tests

Tests exist to provide confidence that the system behaves correctly from the perspective of its users and callers. They do not exist merely to increase coverage, test count, or exercise individual implementation details.

### Default Testing Strategy

When adding or changing behaviour:

1. **Prefer an integration test through a public boundary.**
   Test through the interface that real callers use, such as:
    - a public library API;
    - an HTTP endpoint;
    - a CLI command;
    - a service interface;
    - a database-backed repository;
    - a filesystem or process boundary.

2. **Use end-to-end tests for critical user-visible workflows.**
   Important workflows should be tested from their real entry point through the complete system, with as few mocked components as practical.

3. **Use unit tests only for genuinely isolated logic.**
   Unit tests are appropriate for pure algorithms, parsers, state machines, complicated calculations, and code with many meaningful edge cases. They are not the default choice for ordinary application or service behaviour.

Choose the broadest stable boundary that directly verifies the behaviour being changed. Do not replace a meaningful integration test with an isolated unit test merely because the unit test is easier to write.

### Test Observable Behaviour

Tests MUST assert externally observable outcomes rather than internal implementation details.

Prefer assertions about:

- returned values or errors;
- persisted database state;
- emitted protocol responses;
- generated files;
- visible CLI output and exit status;
- messages sent across a real boundary;
- externally observable state transitions.

Avoid assertions about:

- private methods;
- internal call order;
- how many times an internal helper was invoked;
- intermediate variables;
- the exact internal decomposition of an operation;
- implementation details that may change without changing behaviour.

A refactor that preserves behaviour should normally not require rewriting tests.

### Use Real Components by Default

Integration tests SHOULD use real implementations of components we own.

Prefer:

- a temporary or isolated instance of the real database;
- temporary directories and the real filesystem API;
- real serialization and deserialization;
- a loopback HTTP server and the real networking stack;
- real subprocess execution where process behaviour matters;
- the real repository, service, and handler implementations together.

Do not mock internal modules merely to isolate the code under test.

Mocks, fakes, and stubs are acceptable at true external boundaries when the real dependency is unavailable, nondeterministic, destructive, prohibitively expensive, or controlled by a third party. Place the test double at the outermost practical boundary.

Do not substitute a materially different implementation solely for convenience. For example, an in-memory database or SQLite test does not prove PostgreSQL-specific behaviour.

### Avoid Low-Value Tests

Do not add tests whose primary purpose is to:

- increase line or branch coverage;
- test getters, setters, constructors, or trivial delegation;
- verify that mocked internal methods were called;
- duplicate behaviour already covered by a stronger integration test;
- assert that code merely “does not throw” without checking its result;
- snapshot large unstable structures without asserting their important semantics;
- mirror the production implementation inside the test;
- create one unit test for every function regardless of risk or behaviour.

Do not expose private implementation details or change the production API solely to make isolated unit testing easier.

Fewer high-value tests are preferable to many low-value tests.

### Regression Tests

Every bug fix SHOULD include a regression test that:

1. fails against the broken implementation;
2. exercises the same public boundary through which the bug occurs;
3. demonstrates the incorrect externally observable behaviour;
4. passes after the fix.

Prefer an integration or end-to-end regression test. Use a unit-level regression test only when the defect is genuinely confined to isolated algorithmic logic.

### Required Judgment

Before adding a test, be able to answer:

> What realistic production failure would this test detect?

If there is no concrete answer, do not add the test.

When reporting completed work, state which behaviours were tested and at what boundary. When choosing a unit test or introducing a mock instead of a real integration, briefly explain why the broader test was impractical.
