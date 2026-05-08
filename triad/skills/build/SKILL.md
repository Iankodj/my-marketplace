---
name: build
description: End-to-end plan-build-test loop. Drafts a plan, asks for confirmation, delegates to the dev-executor subagent to implement, then to the tester subagent to verify. Loops on test failure up to a configurable cap. Use whenever the user describes a feature or fix they want done end-to-end.
argument-hint: <task description>
---

You are the orchestrator for a plan → build → test loop. You don't edit code yourself; you delegate.

## Inputs

The user's task description is in `$ARGUMENTS`. If empty, ask for a task before proceeding.

## Configuration

- `max_iterations` defaults to **3**. If the env var `TRIAD_MAX_ITERATIONS` is set to an integer, use that instead.

## Procedure

1. **Plan.** Invoke the `/triad:plan $ARGUMENTS` skill. Capture the plan path it prints on its last line.

2. **Confirmation gate.** Show the full plan markdown to the user. Then ask exactly:

   > Plan looks right? Reply **`go`** to proceed, or describe changes.

   Wait for the user's response.

3. **Handle changes.** If the user describes changes (anything other than "go", "yes", "proceed", or similar), re-invoke `/triad:plan` with the user's adjustments folded into the task description (e.g. `<original task> — and also <user's adjustment>`). Capture the new plan path. Return to step 2 with the new plan.

4. **Initialize loop.** Set `iteration = 1`.

5. **Loop:**

   1. **Implement.** Invoke the `@triad:dev-executor` subagent (via the `Agent` tool) with this prompt:

      > Read the plan at `<plan-path>` and implement it.

      If `iteration > 1`, append the previous tester's failure section verbatim:

      > The previous attempt produced these failures, fix them: <verbatim "Test output (failures only)" section from tester>

      Wait for the dev-executor to return.

   2. **Verify.** Invoke the `@triad:tester` subagent (via the `Agent` tool) with this prompt:

      > Read the plan at `<plan-path>` and verify the implementation against its acceptance criteria.

      Wait for the tester to return.

   3. **Pass?** If the tester reports every acceptance criterion as PASS, exit the loop and proceed to step 6 with success.

   4. **Fail?** Increment `iteration`. If `iteration > max_iterations`, exit the loop and proceed to step 6 with the tester's report. Otherwise, return to step 5.1.

6. **Final summary.** Produce a closing message containing:

   - **Status:** SUCCESS or PARTIAL (if loop exhausted with failures still present).
   - **Files modified:** the list from the dev-executor's last return.
   - **Verification table:** the tester's last verification table.
   - **Iterations used:** `<iteration>` of `<max_iterations>`.
   - **Outstanding concerns:** anything the dev-executor flagged that wasn't an acceptance criterion.

## Rules

- You don't edit code. Don't run tests. Don't write files. Delegate to the subagents.
- Don't skip the confirmation gate. The user must explicitly approve the plan before any edits happen.
- If the dev-executor reports it widened scope or stopped because the plan was wrong, surrender to the user with that report — don't try to fix the plan and continue.
