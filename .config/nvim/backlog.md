# Neovim Configuration Backlog

This file tracks planned improvements that are intentionally deferred.

## Rules

- Choose work by the dependency order below, not merely by document order.
- Keep each completed phase in a separate Git commit.
- Treat every refactor item as a structural change only.
- Preserve existing logic, behavior, keymaps, UI, messages, command output, and timing semantics.
- Do not combine code movement with cleanup, optimization, API redesign, or feature changes.
- Prefer moving existing functions unchanged before improving their internals.
- Make only the smallest import/export changes required to establish module boundaries.
- Record intentional behavior changes as separate feature or fix items and separate Git commits.
- Git Worktree Workflow is a new feature; it must not be mixed into refactor commits.
- Run syntax checks, `git diff --check`, relevant headless smoke tests, and health checks after each phase.
- Capture current behavior with characterization tests before moving high-risk Dadbod, Snacks, LSP, or Diffview logic.
- Compare keymaps, commands, autocmds, and user-visible behavior before and after every refactor phase.
- Mark an item complete only after its acceptance criteria pass.
- Delete this file in the final backlog-completion commit when every item is complete.

## Execution Tracks and Dependency Order

Each commit must belong to exactly one track:

- `test:` captures or verifies existing behavior without production behavior changes.
- `refactor:` moves code or changes module boundaries without behavior changes.
- `fix:` intentionally changes an unsafe or incorrect implementation while preserving the documented user workflow.
- `perf:` intentionally changes implementation timing or resource usage after behavior is covered by tests.
- `feat:` adds new user-facing behavior.
- `docs:` changes documentation only.

Required order:

1. Add the relevant characterization or smoke test from **Tests: Characterization Baseline and Final Verification**.
2. Perform one small structural `refactor:` phase.
3. Verify behavior before considering the refactor complete.
4. Perform related `fix:` work only in a later, separate commit.
5. Build Git Worktree support only after the shared Git foundation is stable.
6. Run final health, startup, and workflow verification.

The Snacks private-API removal is a `fix:`, not a structural refactor. Git Worktree support is a `feat:`. Neither may be included in a `refactor:` commit.

## Refactor Guardrails

Every refactor phase must satisfy all of these conditions:

- No user-facing feature is added or removed.
- No key or command is renamed.
- No picker layout, sort order, default selection, or resume behavior changes.
- No database query, export, result-history, or safety behavior changes.
- No LSP server, capability, formatter, diagnostic, or completion behavior changes.
- No Git or Diffview command semantics change.
- Existing public module functions remain compatible until all callers are migrated.
- If preserving behavior requires a temporary compatibility wrapper, keep it until a later verified phase.
- If a structural move exposes an existing bug, document it as a separate backlog fix instead of fixing it inside the refactor.

## Fix: Snacks Private API Patches

- [x] Inspect the current public Snacks picker and resume APIs.
- [x] Remove overrides of `picker.open` and `picker.Picker.new`.
- [x] Remove overrides of `picker_resume.add` and private `picker_resume._resume`.
- [x] Keep `ensure_unfixed_window()` only at picker entry points that need it.
- [x] Preserve file, grep, buffer, diagnostic, and resume workflows using public APIs.
- [x] Implement this only after capturing current picker and resume behavior.
- [x] Commit this separately from the Snacks module split.

Acceptance criteria:

- No assignment replaces a Snacks function or class method.
- `<leader>ff`, `<leader>fg`, `<leader>fb`, and picker resume still work.
- Pickers do not replace buffers inside `winfixbuf` windows.

## Refactor: Shared Git Foundation

- [x] Add `lua/core/git/repo.lua` for repository root and current-branch resolution.
- [x] Add `lua/core/git/branches.lua` for local/remote branch parsing and status metadata.
- [x] Replace duplicate Git root and branch logic in Snacks and Diffview.
- [x] Keep UI code out of the Git data modules.

Acceptance criteria:

- Snacks and Diffview consume the same Git service modules.
- Git data modules do not depend on Snacks or Diffview.
- Existing branch and base-branch pickers retain their behavior.
- Git command execution remains behaviorally unchanged during this refactor.

Potential performance work, tracked separately as a `fix:` or `perf:` commit:

- [ ] Evaluate asynchronous Git commands after the structural refactor is verified.

## Feature: Git Worktree Workflow

> Deferred by user; do not implement in this refactor cycle.

- [ ] Add `lua/core/git/worktree.lua`.
- [ ] Parse `git worktree list --porcelain` into structured entries.
- [ ] Add `<leader>gw` to open a Snacks worktree picker.
- [ ] Open the selected worktree in a new tab with tab-local `tcd`.
- [ ] Add an optional action to open a worktree in a new tmux window when tmux is available.
- [ ] Create a worktree from an existing branch.
- [ ] Create a worktree with a new branch based on a selected base branch.
- [ ] Validate branch names and target directories before creation.
- [ ] Copy a selected worktree path.
- [ ] Refresh the picker after mutations.
- [ ] Remove a worktree only after confirmation.
- [ ] Refuse to remove the main, current, locked, or dirty worktree by default.
- [ ] Add `git worktree prune` as an explicit picker action.
- [ ] Do not add force deletion in the first version.

Suggested picker mappings:

- `<CR>`: open in a new tab
- `a`: add worktree
- `d`: remove worktree safely
- `p`: prune stale metadata
- `r`: refresh
- `K`: show full path
- `yp`: copy path
- `T`: open in a tmux window

Acceptance criteria:

- Paths containing spaces work correctly.
- No Git command is constructed through shell-string concatenation.
- Dirty worktrees cannot be removed accidentally.
- LSP clients use the correct root after opening files in another worktree.

## Refactor: Dadbod Dependency Cycles

- [x] Add `lua/plugins/dadbod/state.lua`.
- [x] Move shared mutable runtime state into `state.lua`.
- [x] Remove the `init -> history -> init` cycle.
- [x] Remove the `shared -> history -> shared` cycle.
- [x] Make `init.lua` an orchestration entry point instead of a state owner.

State candidates:

- Last result per SQL buffer
- Last dbout directory
- User-closed result windows
- Active query handles
- SQL source-to-output mappings

Acceptance criteria:

- Dadbod modules have no circular `require()` paths.
- State ownership is explicit and documented with LuaCATS.
- Query execution and history navigation retain existing behavior.

## Refactor: Extract Pure SQL Logic

- [x] Add `lua/plugins/dadbod/sql.lua`.
- [x] Move SQL block detection into the module.
- [x] Move comment and semicolon handling into the module.
- [x] Move alias and identifier parsing where appropriate.
- [x] Remove duplicated `is_empty_or_comment()` implementations.
- [x] Remove duplicated `has_valid_semicolon()` implementations.
- [x] Add headless tests for block boundaries, comments, aliases, and quoted identifiers.

Acceptance criteria:

- SQL parsing functions do not depend on windows, pickers, or database processes.
- `query.lua` and completion modules share the same parsing implementation.

## Refactor: Split Dadbod Runtime Responsibilities

- [x] Add `autocmds.lua` for SQL and dbout lifecycle events.
- [x] Add `buffers.lua` for SQL/dbout buffer setup and buffer-local mappings.
- [x] Add `results.lua` for result paths, rename, display, and window lifecycle.
- [x] Add `jobs.lua` for background process tracking and cancellation.
- [x] Move CSV, JSON, INSERT, and IN-clause generation into `export.lua`.
- [x] Move EXPLAIN/ANALYZE behavior into `explain.lua`.
- [x] Keep `query.lua` focused on query execution.
- [x] Keep `cell.lua` focused on cell inspection and text objects.
- [x] Keep completion modules flat because a subdirectory would not improve dependency direction.
- [x] Reduce `dadbod/init.lua` to package setup and orchestration.

Acceptance criteria:

- Each Dadbod module has one documented responsibility.
- Plugin-specific rename behavior no longer lives in `core.utils`.
- Existing PostgreSQL, MySQL, and SQLite workflows pass smoke tests.
- Result history, export, explain, and connection switching still work.

## Refactor: Split Snacks Configuration by Domain

- [x] Convert `lua/plugins/snacks.lua` to `lua/plugins/snacks/init.lua`.
- [x] Add focused modules for files, grep, Git, buffers, and keymaps.
- [x] Keep `snacks.setup()` and package registration in the entry point.
- [x] Keep picker state private to the module that owns the picker.

Suggested structure:

```text
lua/plugins/snacks/
├── init.lua
├── files.lua
├── grep.lua
├── git.lua
├── buffers.lua
└── keymaps.lua
```

Acceptance criteria:

- No behavior is lost.
- No module requires a higher-level UI entry point.
- The entry point contains orchestration rather than picker implementations.

## Refactor: Split LSP Configuration by Responsibility

- [ ] Convert `lua/plugins/lsp.lua` to `lua/plugins/lsp/init.lua`.
- [ ] Move blink.cmp configuration and SQL sorting into `completion.lua`.
- [ ] Move Mason setup and install notifications into `mason.lua`.
- [ ] Move `LspAttach`, diagnostics, and LSP keymaps into `attach.lua`.
- [ ] Keep server-specific overrides under `lsp/servers/`.

Suggested structure:

```text
lua/plugins/lsp/
├── init.lua
├── completion.lua
├── mason.lua
├── attach.lua
└── servers/
```

Acceptance criteria:

- Native `vim.lsp.config()` and `vim.lsp.enable()` remain the only setup path.
- Completion, Mason, and LSP attachment can be reasoned about independently.
- TypeScript, Lua, Go, Python, Rust, GraphQL, and JSON smoke tests pass.

## Fix: Report Critical Module Load Failures

- [ ] Define which modules are critical and which are optional.
- [ ] Report critical Snacks, Treesitter, completion, Mason, and LSP setup failures.
- [ ] Keep optional plugin failures non-fatal where appropriate.
- [ ] Implement only after the LSP and Snacks structural refactors are verified.

Acceptance criteria:

- Critical failures are visible and actionable.
- Optional tooling can still fail without preventing core editing.
- This behavior change is committed separately from module movement.

## Refactor: Clean Core Boundaries

- [ ] Split pack commands from `core/commands.lua`.
- [ ] Split environment loading from `core/commands.lua`.
- [ ] Move general autocommands into a dedicated core module.
- [ ] Split notification messages from `core/utils.lua`.
- [ ] Move generic file operations into `core/files.lua`.
- [ ] Remove Dadbod-specific behavior from generic core modules.

Suggested structure:

```text
lua/core/
├── commands/
│   ├── init.lua
│   ├── pack.lua
│   └── env.lua
├── autocmds.lua
├── files.lua
├── messages.lua
└── notify.lua
```

Acceptance criteria:

- Core modules do not depend on plugin-specific modules or filetypes.
- Commands, events, messages, and file operations have clear owners.
- Startup performance remains below 100 ms on the current machine.

## Refactor: Diffview Cleanup

- [ ] Move reusable Git operations to `core/git/`.
- [ ] Keep Diffview configuration and review UI behavior in `plugins/diffview.lua`.
- [ ] Keep only lazy-loading and user-facing keymaps under `core/keymaps/diffview.lua`.
- [ ] Preserve reviewed-file markers, base-branch selection, hover, and relative-path copy.

Acceptance criteria:

- Diffview modules do not duplicate Git branch parsing.
- `core/keymaps/diffview.lua` contains mappings and thin orchestration only.
- Diffview, file history, and merge-feature workflows pass smoke tests.

## Tests: Characterization Baseline and Final Verification

- [x] Capture current keymaps, commands, and autocmd registrations before the first refactor.
- [x] Capture current Snacks picker and resume behavior before removing private patches.
- [x] Capture current Dadbod module behavior before changing state ownership.
- [x] Capture current LSP, completion, and Mason behavior before splitting modules.
- [x] Add headless tests for pure Git parsing.
- [x] Add headless tests for SQL parsing and result-path generation.
- [ ] Add smoke tests for keymap registration and plugin entry points.
- [ ] Document external dependencies: Git, ripgrep, fd, database CLIs, tmux, and OSC 52 terminal support.
- [ ] Run `:checkhealth` after the final refactor.
- [ ] Measure empty startup and first-file startup after the final refactor.
- [ ] Confirm `nvim-pack-lock.json` remains synchronized.

Final acceptance criteria:

- No private or global API monkey-patches remain.
- No circular module dependencies remain.
- Startup remains below 100 ms.
- `git diff --check` and all headless tests pass.
- Worktree, Diffview, LSP, formatting, DAP, session, picker, and Dadbod workflows work.
- All checklist items above are complete.
- Delete `backlog.md` and commit its deletion as the final backlog-completion change.
