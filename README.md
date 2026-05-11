# my-plugins marketplace

This folder is a Claude Code plugin marketplace. Claude Code discovers it from `.claude-plugin/marketplace.json`, which currently publishes the `triad` plugin from `./triad`.

For local VS Code hook testing, workspace hooks must be placed under `.github/hooks/`. This repository includes `.github/hooks/triad-auto-format.json`, which calls the Triad formatter script in `triad/hooks/auto-format.sh`.

## Install from this local marketplace

From Claude Code, add this folder as a marketplace and install `triad`:

```text
/plugin marketplace add /Users/idjemere/repos/my-plugins/plugins
/plugin install triad@my-plugins
```

After changing marketplace metadata or plugin versions, refresh Claude Code's listing:

```text
/plugin marketplace update my-plugins
```

## Published plugins

### triad

A Claude Code plugin that wraps a real plan → build → test development loop. Three skills, two subagents, one MCP server, one hook.

```
/triad:build add a healthcheck endpoint that returns 200
```

triad drafts a plan, asks you to confirm it, hands the plan to a `dev-executor` subagent that implements the changes, then to a `tester` subagent that verifies the result against the plan's acceptance criteria. Files saved by the dev-executor are auto-formatted on the way out. Library docs are pulled live from context7 during planning and implementation.

## Components

| Entry point | What it does |
|---|---|
| `/triad:plan <task>` | Drafts a structured plan with goal, affected files, dependencies, and acceptance criteria. Writes to `.triad/plans/`, echoes to chat. |
| `/triad:build <task>` | End-to-end loop: plan → confirm → dev-executor → tester. Bounded retry on test failure (cap configurable). |
| `/triad:test [scope]` | Runs the project's test suite. Auto-detects the runner from project files. |
| `@triad:dev-executor` | Implements code from a plan path. Restricted to non-destructive operations. Self-validates via `/triad:test`. |
| `@triad:tester` | Read-only validator. Maps acceptance criteria → PASS/FAIL with the underlying test output. |

## Building blocks

triad showcases all four canonical Claude Code plugin building blocks composing in one workflow:

- **Skills** — `/triad:plan`, `/triad:build`, `/triad:test`
- **Subagents** — `@triad:dev-executor`, `@triad:tester`
- **MCP** — context7 (library docs lookup, registered in `.mcp.json`)
- **Hooks** — PostToolUse on Edit/Write triggers `hooks/auto-format.sh`, which dispatches by file extension to prettier / ruff / gofmt / rustfmt

## Install

### Local development / testing

```bash
git clone <repo-url> triad
cd <your-project>
claude --plugin-dir /path/to/triad
```

### From a marketplace (once published)

```text
/plugin marketplace add /Users/idjemere/repos/my-plugins/plugins
/plugin install triad@my-plugins
```

## Configuration

| Env var | Effect | Default |
|---|---|---|
| `TRIAD_NO_AUTOFORMAT` | Set to `1` to bypass the auto-format hook (e.g. if you have your own format-on-save tooling). | `0` |
| `TRIAD_MAX_ITERATIONS` | Override the `/triad:build` retry cap. Triad re-invokes `@triad:dev-executor` up to this many times when tests fail. | `3` |
| `TRIAD_HOOK_TRACE` | Set to `1` to append a diagnostic line per hook invocation. Useful when debugging whether the hook is firing, which formatter ran, or what payload the host sent (especially under VS Code Copilot, which ignores the `matcher` field). | `0` |
| `TRIAD_HOOK_LOG` | Destination for the trace lines when `TRIAD_HOOK_TRACE=1`. If unset, the hook writes to `<cwd>/.triad/hook.log` (project-level, next to plan files), falling back to `/tmp/triad-hook.log` if `.triad/` can't be created. | _(see Effect)_ |
| `TRIAD_HOOK_NOTIFY` | Set to `0` to suppress the system-reminder the hook injects back into the agent's context after a formatter runs (the message that lets the agent tell you "auto-formatted X with prettier"). | `1` |

## Plan format

Plans are markdown files with structured frontmatter, written to `<cwd>/.triad/plans/<slug>-<timestamp>.md`. Add `.triad/` to your `.gitignore`.

```markdown
---
goal: Add dark mode toggle to settings page
affected_files:
  - src/components/SettingsPage.tsx
  - src/styles/themes.ts
dependencies:
  - none
acceptance_criteria:
  - Toggle persists across page reloads
  - Theme applies to all child components
  - Existing theme tests still pass
---

# Plan: Add dark mode toggle

## Steps

1. Extend `themes.ts` with a `dark` palette …
2. …

## Risks

- …
```

The frontmatter is the contract between the planner, dev-executor, and tester. The `acceptance_criteria` list is what the tester checks.

## Auto-format support

The hook formats files on every Edit / Write, dispatching by extension:

| Extension | Formatter |
|---|---|
| `.js` `.jsx` `.ts` `.tsx` `.mjs` `.cjs` `.json` `.css` `.html` `.md` `.yaml` `.yml` | `prettier --write` |
| `.py` | `ruff format` |
| `.go` | `gofmt -w` |
| `.rs` | `rustfmt` |

For each formatter, the hook walks up from the edited file looking for a project-local `node_modules/.bin/<tool>` binary first, and falls back to a regular `PATH` lookup. So a project devDep like `prettier` works without a global install. If neither resolution finds the binary, the hook silently no-ops. Project-local config (`.prettierrc`, `pyproject.toml`, `rustfmt.toml`) is respected — the script doesn't pass `--config` flags.

The packaged `PostToolUse` matcher in `triad/hooks/hooks.json` covers both Claude Code (`Write|Edit|MultiEdit`) and VS Code Copilot (`create_file|replace_string_in_file|insert_edit_into_file|apply_patch`) tool names. For VS Code workspace testing, install the hook under `.github/hooks/` as shown by `.github/hooks/triad-auto-format.json`; files elsewhere in the repo are source assets and are not discovered as active workspace hooks. The script also enforces the same mutating-tool allowlist before formatting so read-only tools such as file reads are skipped even if their payload includes a valid file path.

## Examples

See [`examples/`](./examples/) for sample plans and test fixtures.

## License

MIT — see [LICENSE](./LICENSE).
