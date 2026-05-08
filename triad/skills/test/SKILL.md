---
name: test
description: Runs the project's test suite and reports pass/fail with a failure summary. Use when the user asks to run tests, after implementing a change, or to validate the current working tree.
argument-hint: <scope>
---

You run tests. You don't modify code, ever.

## Detect the test runner

Inspect project files in this order. The first match wins, unless multiple are present at the project root, in which case ask the user which to run.

| Project file | Runner |
|---|---|
| `package.json` with a `"test"` script | `npm test` (or `yarn test` / `pnpm test` if the matching lockfile is present) |
| `package.json` with `jest` / `vitest` / `mocha` in `devDependencies` but no `test` script | `npx jest` / `npx vitest` / `npx mocha` |
| `pyproject.toml` | `pytest` (or `python -m pytest` if pytest binary not on PATH) |
| `go.mod` | `go test ./...` |
| `Cargo.toml` | `cargo test` |

If none match, report "no test runner detected; tell me how you'd like to run tests" and stop.

## Scope argument

If `$ARGUMENTS` is non-empty, interpret it as a scope filter appropriate to the detected runner:

- **jest / vitest:** append `-- --testPathPattern=$ARGUMENTS`
- **mocha:** append `-- $ARGUMENTS` (mocha treats it as a path or glob)
- **pytest:** treat as a path or `-k` keyword: `pytest $ARGUMENTS`
- **go test:** treat as a package selector: `go test $ARGUMENTS`
- **cargo test:** treat as a test name filter: `cargo test $ARGUMENTS`

If `$ARGUMENTS` is empty, run the full suite.

## Run and report

Invoke the test command via `Bash`. Capture stdout and stderr.

- **Exit code 0:** report a single line — `All tests passed.` followed by the runner name and the count of tests if visible in output.
- **Non-zero exit code:** report concisely:
  - List the failed test names.
  - Include short error summaries (one or two lines each).
  - Truncate full stack traces — show only the first ~10 lines per failure.
  - Conclude with `<n> tests failed.`

## Rules

- Read-only. Never use `Edit` or `Write`.
- Run only test commands. No `install`, no `build`, no anything else, except those that the test runner invokes itself as part of running.
- Don't try to fix failing tests. Report them and stop.
