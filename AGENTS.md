# Project agent workflow

## Purpose and scope

Work autonomously on the user's requested scope, using the Backlog CLI
to plan, assign, execute, and document tasks.

When asked to work through the backlog, continue until all eligible
tasks are complete or the remaining tasks require user input.

Discussion, review, and planning requests do not automatically start
implementation.

Ask about consequential unresolved product, architecture, security,
or destructive decisions. Resolve routine implementation details
using project conventions and judgment.

## Agent identity and roster

Read agents.json at the start of each session. If the file does not
exist, create one specific for this project, based on the structure
of `agents.example.json` (no need to use it verbatim; agents and roles
can vary per project).

Each session operates under one agent nickname. The orchestrator
assigns nicknames when starting workers. A standalone session uses
defaultAgent unless the user specifies otherwise.

Agent nicknames must match backlog assignee names exactly.

Use the smallest useful number of workers. Delegate independent work
when it provides a clear benefit; handle small or tightly coupled
work directly.

The roster describes roles and permissions. It does not itself
launch workers or enforce filesystem permissions.

## Orchestration and assignment

The default agent is the orchestrator.

The orchestrator:

- Turns agreed requirements into actionable backlog tasks.
- Defines acceptance criteria, dependencies, and priorities.
- Assigns each execution task to one accountable agent.
- Starts workers with their nickname, task scope, and relevant context.
- Coordinates overlapping work, handoffs, and integration.
- Keeps the overall backlog accurate.

In a multiagent run, workers pick up eligible tasks assigned to their
nickname. Workers do not take another agent's tasks without a handoff
or reassignment by the orchestrator.

In a standalone run, the default agent may execute eligible tasks
assigned to any agent within the user's requested scope. Record the
solo takeover in the task notes; reassignment is optional.

An assignment does not override an existing active claim.

Split independently executable work into separate tasks rather than
giving multiple workers concurrent ownership of one task.

## Task execution

Before starting a task:

1. Read its description, acceptance criteria, dependencies, and notes.
2. Confirm it is within scope, unblocked, and permitted by your role.
3. Acquire its active claim.
4. Set its status to In Progress through the Backlog CLI.

While working:

- Keep implementation plans, decisions, blockers, and evidence in
  the task.
- Append progress notes without replacing another agent's notes.
- Keep changes scoped and preserve unrelated work.
- Record newly discovered work as tasks; do not silently expand scope.
- If blocked, record the reason and required next action, then
  release the claim and continue independent eligible work.

Mark a task Done only when:

- Its acceptance criteria are satisfied.
- Relevant validation has passed, with limitations documented.
- Its changes are integrated into the main working tree.
- Any required visual evidence and completion summary are recorded.
- User-facing features and substantial UI changes are reflected in the README (see "Public docs"), or the task notes
  say why they are not needed.

Writing workers update their own tasks through the CLI. Read-only
workers return findings and proposed updates to the orchestrator,
which records them.

Do not mark blocked or partially completed work Done.

## Local coordination

The backlog is the source of truth for requirements, assignments,
dependencies, progress, decisions, and completion evidence.

Use .local/coordination/ only for runtime coordination:

- sessions/<session-id>.json: nickname, mode, activity, and owned claims.
- claims/<task-id>/owner.json: owning session and working directory.
- backlog-write.lock/: short-lived lock for backlog mutations.

Acquire task claims by atomically creating their claim directory.
If it already exists, treat the task as claimed.

Create backlog-write.lock/ atomically before mutating the backlog.
Record the owning session, keep the operation brief, and release
the lock afterward.

Do not hold the backlog write lock while implementing, testing,
waiting for workers, or waiting for user input.

Release claims when work finishes, is handed off, or is blocked.
Do not reclaim claims or locks based only on their age: first confirm
the owning session has stopped or explicitly released ownership.

At session startup, reconcile existing claims with the backlog and
live workers before taking new work.

Do not duplicate task descriptions or progress histories in runtime
files. Do not delete another session's coordination state.

## Backlog repository boundary

backlog/ is ignored by the main repository and has its own local
Git repository.

Agents may update backlog content through the Backlog CLI, but must
not stage, commit, push, reset, or clean the backlog repository.

Backlog is auto-committed automatically, but a dirty backlog state
is expected and is not a blocker.

Dirty application state is also not a blocker by itself. Inspect
ownership and overlap, preserve existing changes, and continue work
that can be completed safely.

Application commits remain subject to agents.json permissions and
the existing Git and staged-change rules.

If agents have all finished their work and there are still files
pending to be committed, the default/main agent may do so into
proper commits, before starting any other agents again.

## Shared work and worktrees

Avoid overlapping edits between workers in the same working tree.
The orchestrator assigns distinct file ownership or serializes
conflicting work.

Use worktrees when isolation provides a clear benefit. Record the
working directory in the task claim.

Before closing a worktree, integrate and verify its needed changes
in the main working tree. Remove it only after confirming no needed
work remains.

## Scratch space

Use .local/agents/<nickname>/<session-id>/ for session scratch work.

.local/coordination/ is operational state, not disposable scratch.
Preserve .local/data/ and .local/keep/ if they exist.

canWrite: false still permits an agent to write its own scratch and
session coordination state, but not source files or backlog content.

## Visual progress

For UI work, send screenshots in chat after important visual changes
and at completion.

When requesting a consequential UI decision, show the current result
with a disposable screenshot when practical.

Store final representative screenshots in `backlog/assets/` and link
them from the relevant task. Keep intermediate captures in scratch.

## Files that LLMs and Agents should not use as context

Any file matching these patterns, should not be used as context:

- ./**/*.prompt.txt
- ./**/*.prompt.md

## Other things to keep in mind

From time to time, please format docs and other code via `npx -y oxfmt .`
before comitting if you are only the agent running.

## QuickEdit project

Native macOS 26 code viewer and editor for small, quick edits (SwiftUI + AppKit, Swift 6, SwiftPM): a modern TextEdit
and a lighter Sublime Text, not an IDE. Sibling of NoteMD (`../notemd`), which some editor, preview and voice code was
copied from. Decisions live in `backlog/decisions/` (platform, syntax, safe editing, preview/voice, file types).

### Commands

| Command                           | What it does                                                                |
| --------------------------------- | --------------------------------------------------------------------------- |
| `swift build` / `make build`      | Debug build of all targets                                                  |
| `swift test` / `make test`        | Core unit tests (Swift Testing)                                             |
| `make test-syntax`                | `Packages/QuickEditSyntax` tests (grammars, queries, language detection)    |
| `make app`                        | Release `build/QuickEdit.app` (ad-hoc signed unless `SIGN_IDENTITY` is set) |
| `make dev` / `make run`           | Debug `build/QuickEdit Dev.app` (own bundle id and defaults)                |
| `make test-app` / `make run-test` | Background agent build `build/QuickEdit Test.app`                           |
| `make install`                    | Quits the installed copy and installs the release build to /Applications    |
| `make release`                    | App, zip, DMG and SHA256SUMS in `build/release` (ad-hoc without credentials) |
| `make build-notarized`            | Same, signed with the Keychain's Developer ID and notarized + stapled        |
| `make install-notarized`          | Installs the notarized build to /Applications                               |
| `make icon`                       | Redraws `Resources/AppIcon.icon` from `scripts/make-icon.swift`             |
| `make grammars`                   | Re-vendors the tree-sitter grammars pinned in the syntax package lock file  |

### Layout

| Path                                            | Contents                                                                     |
| ----------------------------------------------- | ---------------------------------------------------------------------------- |
| `Sources/QuickEditCore`                         | UI-free: text format (encoding, line endings, indentation), `.editorconfig`, |
|                                                 | risky characters, property lists, Markdown rendering, voice note paths       |
| `Sources/QuickEdit/App`                         | App entry, delegate, settings, variants, menus                               |
| `Sources/QuickEdit/Document`                    | `NSDocument`, window controller, status bar                                  |
| `Sources/QuickEdit/Editor`                      | Text view, line number ruler, invisibles, line commands, highlighting glue   |
| `Sources/QuickEdit/Preview`, `Voice`            | Markdown/HTML preview, voice recorder, on-device transcription               |
| `Sources/QuickEdit/Debug`                       | URL scheme handler; DEBUG-only test hooks                                    |
| `Sources/QuickEditQuickLook`                    | Quick Look extension: text `.ts` as plain text, video back to the system     |
| `Packages/QuickEditSyntax`                      | Local package: language registry, vendored tree-sitter grammars, highlighter |
| `Resources/`                                    | Info.plist, privacy manifest, `AppIcon.icon`                                 |
| `scripts/`                                      | `build-app.sh`, `release.sh`, `make-icon.swift`, `window-screenshot.swift`   |
| `VERSION`                                       | The marketing version; the build number is the commit count                  |

### Releases

`make build-notarized` signs with the Keychain's "Developer ID Application" identity (hardened runtime, secure
timestamp, `Resources/QuickEdit.entitlements`) and notarizes with the notarytool profile `NOTARY_PROFILE` (default
`lamina`, the profile Lamina uses for the same team). Notarization uploads the build to Apple: run it only when the
user asks for a release or a notarized build. Bump `VERSION` for each release.

### Public docs

The README is part of the product. Any task that adds, removes or renames a user-facing feature, or substantially
changes the UI, updates the README's feature list and screenshots in the same task. There's no website or intro video
yet.

### Builds

| Build          | Bundle id                    | Scheme              | Who uses it                                            |
| -------------- | ---------------------------- | ------------------- | ------------------------------------------------------ |
| QuickEdit      | `com.itsjavi.quickedit`      | `quickedit://`      | The user. Agents never launch or install it            |
| QuickEdit Dev  | `com.itsjavi.quickedit.dev`  | `quickedit-dev://`  | Developer debug runs                                   |
| QuickEdit Test | `com.itsjavi.quickedit.test` | `quickedit-test://` | Agents: `LSUIElement`, never activates or steals focus |

The Quick Look extension is embedded in the release build only (`QUICKLOOK=1 make test-app` adds it to another
variant), so agent builds don't register a system-wide Quick Look provider.

### Driving the Test build

Launch with `open -g "build/QuickEdit Test.app"` and send hooks with
`open -g -a "$PWD/build/QuickEdit Test.app" "quickedit-test://<verb>?<query>"`. Hooks run only in the Test variant and
only against files under `/private/tmp` or `/private/var/folders`. Add `doc=<path suffix>` to target a document window
(default: the frontmost document).

- `ui/open?path=`, `ui/new?text=`, `ui/close`, `ui/save`, `ui/window-size?w=&h=`, `ui/appearance?value=system|light|dark`
- `ui/type?text=`, `ui/select?location=&length=`, `ui/goto-line?line=`
- `ui/command?name=` (editor and menu commands by selector name, e.g. `moveLineUp:`, `toggleComment:`)
- `ui/mode?value=edit|split|preview`, `ui/remote-content?value=0|1`, `ui/setting?name=line-numbers|invisibles|wrap|current-line|font-size&value=`
- `ui/voice-start?seconds=|from=` (recorder with the microphone replaced by a tone or clip), `ui/voice-stop`, `ui/voice-cancel`,
  `ui/transcript?src=&text=` (inserts a transcript like the sheet's Insert)
- `ui/indentation?style=tabs|spaces&width=[&convert=1]`, `ui/line-endings?value=lf|crlf|cr`
- `debug/state?out=/private/tmp/state.txt` writes a `key: value` state dump; `debug/preview?out=` dumps the preview
  page's text and computed colours; `debug/snapshot?out=` renders the editor in-process (PNG)

The Test build never shows alerts, sheets or error dialogs (a sheet can make its window key and activate the app):
`Dialogs` records them as `suppressedDialog:` in the state dump. Windows aren't restorable there either. After a hook
sequence, check `lsappinfo front` didn't change. Window captures don't include WKWebView content; use `debug/preview`.

Capture windows without activating the app: `swift scripts/window-screenshot.swift "QuickEdit Test" /private/tmp/shot`.
An open sheet blocks quitting (standard AppKit): close sheets before `quit`, or `pkill` the Test build.
Real clicks, drags, Finder "Open With" and menu shortcuts still need a human check in the Dev build.

### Never take over the user's Mac

The user keeps working while agents run, so verification must never steal focus, move the pointer or type.

- Verify UI only through the Test build: hooks, `debug/state` and `scripts/window-screenshot.swift`. Launch it and send
  hooks with `open -g`; it's an `LSUIElement` app and never activates.
- Don't use computer use or screen control, AppleScript or System Events clicks and keystrokes, or anything else that
  activates an app or drives the pointer or keyboard, and don't launch the Dev or release builds (`make dev`,
  `make run`), unless the user said yes in chat to that specific check. Ask first, saying what you'd click and why
  hooks can't cover it.
- Don't run `qlmanage -p` or anything else that opens a Quick Look panel.
- When behavior needs a real click (context menus, drags, shortcuts), prefer a DEBUG hook that exercises the same code
  path in-process. Otherwise list the check in the task notes and the final message for the user to do.
- The orchestrator repeats this rule in every worker brief.
