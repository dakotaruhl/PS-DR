# HelpDesk-MOC Changelog

## v1.13.83 - Update review mouse-scroll KeyInfo fix

- Fixes the completed `U: Update` review screen so mouse-wheel/terminal scroll input returned by `$Host.UI.RawUI.ReadKey()` no longer throws a `KeyInfo` to `ConsoleKeyInfo` conversion error.
- Normalizes both host `KeyInfo` and `ConsoleKeyInfo` input before processing PgUp/PgDn, Up/Down, Home/End, Enter, Esc, Backspace, or Q.
- Keeps the combined update summary and HelpDesk-MOC update-output review behavior from v1.13.82 unchanged.

## v1.13.82 - Combined update summary and update-output review

- Replaces separate update result lines with one combined `Update summary` line for the HelpDesk-MOC menu script, `CHANGELOG.md`, and child scripts.
- Keeps the completed `U: Update` screen open for review and supports PgUp/PgDn, Up/Down, Home/End, and mouse-wheel-style scroll input before returning to the menu.
- Prevents scroll input during update review from immediately returning to the HelpDesk-MOC Home menu.


## v1.13.81 - Self-update changelog refresh

- Updates `U: Update` so it also checks for `CHANGELOG.md` in the same SharePoint folder as the HelpDesk-MOC menu script.
- Downloads `CHANGELOG.md` beside the local HelpDesk-MOC script, backs up an existing local changelog before replacing it, and skips cleanly if the remote changelog is missing.
- Keeps child-script update behavior, staging cleanup, and HelpDesk-MOC limited Exchange Online validation unchanged.

## v1.13.80 - Run-console native progress suppression fix

- Suppresses native PowerShell web progress records during child-script execution so messages such as `Reading web response stream [Downloaded: ...]` cannot overwrite the `Lines / Showing` strip or input pane.
- Keeps child-script `Write-Progress` integration working through the MOC progress proxy while silencing host-level progress emitted by underlying web/Graph/EXO cmdlets.
- Adds filtering for any captured web-progress artifact lines before they reach the run-console output buffer.


## v1.13.79 - Run Console Line-Status Separate Border Fix

- Rendered the run-console `Lines / Showing` status strip as a separate mini-box with its own explicit bottom border.
- Added a separate input-pane top border so repeated HelpDesk child-script input redraws, such as `DisableM365Accounts.ps1`, cannot visually swallow the line-status divider.
- Adjusted run-console viewport reservation by one row to keep the footer and input pane inside the terminal frame.
- Preserved the HelpDesk-MOC limited Exchange Online validation behavior.

## v1.13.78 - Self-update restart countdown

- Adds a visible 15-second countdown after a menu self-update is applied so the operator has time to read the update-complete screen before the current menu session exits.
- Keeps the automatic relaunch behavior from v1.13.77, but now redraws the update pane each second with the remaining restart time.
- Continues to avoid Ctrl+C simulation; the current menu exits cleanly and the updated menu opens in a new PowerShell window.

## v1.13.77 - Self-update automatic relaunch

- Changes U: Update behavior after a menu script update is applied: MOC now informs the operator that a forced restart is required, closes the current menu session cleanly, and automatically opens the updated menu in a new PowerShell window.
- Avoids simulating Ctrl+C; the old menu process exits cleanly after disconnecting parent-owned sessions and writing the normal shutdown summary.
- Keeps child-script update checks, staging cleanup, and backup behavior from prior releases.

## v1.13.76 - Run-console line-status border fix

- Fixes active child-script redraws where the `Lines: ... | Showing: ...` status strip could appear without a visible bottom divider while a child script was waiting for input.
- Renders the line-status strip and input pane as a joined stacked frame, preventing the input pane redraw from visually swallowing the line-status border.
- Keeps prior v1.13.75 behavior that hides internal update-staging folders and root-level scripts from the menu.

## v1.13.75 - Update staging cleanup and menu hide fix

- Hides internal dot-prefixed folders such as `.MOC-Update-Staging` and `.MOC-Update-Backups` from the menu.
- Removes root-level scripts from the displayed folder list so the `Root` folder no longer appears.
- Cleans `.MOC-Update-Staging` before and after self-update checks, including `ChildScripts` staging content.
- Preserves update backups while hiding the backup folder from the menu.


- v1.13.74 - Adds resilient child-script update root fallback for U: Update. This fixes HelpDesk-MOC configurations that still point child-script updates at Binaries/MOC while the menu and HelpDesk child scripts live under Binaries/Helpdesk-MOC.
- v1.13.73 - Adds the same lazy Purview/Security & Compliance framework while continuing to skip Purview during A: Auth for HelpDesk-MOC unless a future allowed child script explicitly requires it. Moves the long in-script changelog to CHANGELOG.md.

## Historical in-script changelog moved from the menu header

- v1.13.72 - Adds SharePoint self-update authorization guidance when U: Update cannot access the configured Graph/SharePoint update source. Preserves HelpDesk-MOC limited Exchange Online validation behavior.
- v1.13.71 - Fixes self-update run-console OutputBuffer binding so U: Update can start even when the update output buffer is initially empty. Preserves the HelpDesk-MOC limited Exchange Online validation behavior.
- v1.13.70 - Adjusts HelpDesk-MOC authentication to use limited Exchange Online session validation that does not require Get-OrganizationConfig, and skips the parent Purview search-only session because the HelpDesk child-script scope does not require it.
- v1.13.69 - Fixes first-run configuration Quit handling so Q exits cleanly without emitting an OperationCanceledException/error after the normal shutdown summary.
- v1.13.64 - Adds a built-in C: Configure menu and first-run configuration wizard. Local JSON config overlays menu variables without storing client secrets; warnings remind users not to change settings unless they understand the impact.
1.13.63 - Fixes child-script discovery so scripts placed next to the menu or in nested child folders are discovered, while preserving HelpDesk allow-list filtering.
1.13.62 - Adds OS-aware update unblocking for validated downloaded PowerShell files and simplifies folder script counts to parenthesized totals only.
1.13.61 - Adds SharePoint/Graph self-update support for the menu and recursive child-script update checks.
- U: Update now checks the configured SharePoint folder for a newer menu script and matching child-script updates.
- Newly discovered child scripts are listed and require an Install missing scripts? Y/N confirmation before local folders/scripts are created.
- HelpDesk-MOC variant restricts visible/update-managed child scripts to the configured HelpDesk script patterns.
1.13.60 - Restores a visible normal terminal after quitting MOC by printing a persistent exit summary after leaving the alternate screen buffer; prevents the apparent blank black terminal introduced by alternate-screen rendering.
1.13.59 - Forces a fresh prefixed Purview search-only session during authentication so Start-ComplianceSearch receives EnableSearchOnlySession; avoids reusing stale pre-search-only connections.
1.13.58 - Corrected Read-MOCMenuChoice to number unnumbered child options automatically, detect existing exit entries semantically, and prevent duplicate hardcoded 4. Exit entries.

- v1.13.57 - 2026-07-23
  - Enables the parent-owned Microsoft Purview search-only session by passing EnableSearchOnlySession to Connect-IPPSSession.
  - Makes the prefixed compliance-search cmdlets available to MOC child scripts that create or review read-only eDiscovery searches.
  - Extends Purview session validation to require both Get-ERSCRoleGroup and Get-ERSCComplianceSearch before the shared session is marked healthy.

- v1.13.56 - Removes the SharePoint Online Management Shell connection from the parent MOC authentication flow. MOC authentication now returns to Graph, Exchange Online, Purview, and Azure only; SharePoint Online Management Shell is intentionally not imported, connected, validated, or disconnected by the parent menu.

- v1.13.53 - Restores the parent menu to the stable v1.13.50 base and reapplies child-run-console severity coloring narrowly. Only child output written through Write-MOCOutputLine -Level is tagged; Authentication, navigation, and shared menu state paths are left unchanged.

- v1.13.50 - Normalizes child-menu prompt choice hints, prevents duplicate q/Q/Esc text, and handles actual Escape key presses in child menu prompts.



v1.13.49 - 2026-07-10
- Suppresses raw Az.Accounts PSConfig output produced during authentication configuration.
- Replaces repeated Az.Accounts configuration messages with one clean MOC authentication-pane line: Az.Accounts configuration validated.
- Keeps DefaultSubscriptionForLogin configuration output suppressed while preserving the existing subscription-selection behavior.

v1.13.48 - 2026-07-10
- Hides the Tenant value in the MOC Header / Tenant Status Header until a parent MOC authentication session is connected.
- Displays the masked authenticated tenant ID after Graph authentication succeeds, matching the existing Organization behavior.
- Retains the configured tenant ID for authentication validation but no longer displays it before authentication.

v1.13.47 - 2026-07-10
- Fixes MOC-managed child input menu redraw behavior so PgUp/PgDn, Up/Down, Home/End, and mouse-wheel translated review keys do not append duplicate menu text while waiting for input.
- Keeps Area 6 line count stable during output review; only the visible range changes when the operator scrolls.
- Preserves child-script boundary ownership: menu/options in Area 5, input state in Area 7, scroll/line status in Area 6 owned by the parent renderer.

v1.13.46 - 2026-06-30
- Routes Az.Accounts configuration warnings and authentication-related warning/information output into the MOC authentication pane or suppresses known noisy host-only messages so warnings do not bleed into the Input pane or below the MOC frame.
- Removes automatic Windows device-code authentication because suppressing that flow can hide the device-code instructions and make authentication look stuck; MOC now relies on WAM-disabled browser authentication where supported.
- Adds an authentication redraw checkpoint immediately before Azure sign-in so any raw host text is cleared before returning to the MOC frame.

v1.13.45 - 2026-06-30
- Improves interactive Azure authentication hygiene by disabling process-scope WAM/login-experience prompts when supported by the installed Az.Accounts module.
- Suppresses Azure subscription/login announcement text that could write below the MOC frame and redraws the authentication pane after interactive login steps to clear raw host output.
- Updates the header User value to the authenticated Microsoft 365/Azure UPN after successful authentication and resets it to the local session user after disconnect or authentication failure.

v1.13.43 - 2026-06-30
- Fixes Selected Script Details description wrapping so wrapped rows account for the two-space description indent before rendering inside the pane.
- Prevents description words from being clipped at the right pane border, such as long rows ending in partial words.
- Keeps the details pane border stable while preserving the existing metadata, Terminal, and output-capture behavior from v1.13.42.

v1.13.42 - 2026-06-30
- Improves MOC Terminal multiline execution output capture by explicitly redirecting PowerShell host/information, verbose, warning, debug, error, and success streams back into the Run Output pane.
- Replaces the ambiguous Terminal "(no output)" message with a clearer note when a command completes silently, such as when defining functions or assigning variables only.
- Adds lightweight PowerShell syntax highlighting to the Terminal Paste Editor preview without changing the stored command text or execution behavior.

v1.13.41 - 2026-06-30
- Fixes Terminal Paste Editor parameter binding when pasted blocks contain blank lines or when the paste buffer temporarily contains an empty first/last line.
- Allows empty string entries in paste-editor line arrays so multiline blocks with spacing can be reviewed, edited, and parsed without throwing a parameter-binding error.
- Preserves the v1.13.40 paste editor behavior while improving blank-line handling.

v1.13.40 - 2026-06-30
- Adds a MOC Terminal multiline paste editor for buffered script blocks.
- Allows technicians to scroll pasted code, select lines, edit a selected line, delete a line, insert a line, cancel the buffer, and run only after parser validation.
- Shows a fixed-height code preview in the MOC Input pane instead of hiding the pasted block or expanding the pane to the full block size.
- Summarizes multiline command execution in the Run Output pane to keep long pasted commands contained inside the MOC frame.

v1.13.37 - 2026-06-30
- Corrects the metadata .VERSION value so the MOC Header / Tenant Status Header displays v1.13.37 instead of the previous metadata value.
- Retains the v1.13.36 input-pane stale-prompt clearing fix and authentication output scroll-to-latest behavior.

v1.13.36 - 2026-06-30
- Clears parent-owned Input / Run Footer Pane prompt state immediately after MOC-managed input is submitted.
- Applies the same wrapped-row auto-follow and completion scroll-to-bottom behavior to the MOC Shared Authentication Session renderer that child-script run consoles use.
- Fixes Authentication Session completion views that showed the first output rows even when additional output existed below the visible Run Output Pane.

v1.13.34 - 2026-06-30
- Restores child run-console auto-follow and live output-review behavior from v1.13.31 while preserving the v1.13.33 input prompt formatting fix.
- Calculates child run-console scroll ranges using wrapped display rows instead of raw output-buffer lines so the output pane follows the newest visible rows correctly.
- Keeps PgUp/PgDn, Up/Down, Home/End available for output review during active child-script execution; End resumes latest-output auto-follow.
- Renders parent-owned input prompts with a colon separator instead of a greater-than prompt marker and avoids duplicate punctuation.

v1.13.29 - 2026-06-29
- Adds bracketed-paste mode while MOC Terminal is active so supported hosts, including Windows Terminal and common Linux terminals, send pasted multiline blocks as one paste transaction.
- Buffers bracketed pasted content without executing each line separately, then runs the completed command only after the technician presses Enter.
- Forces a hard redraw after large paste batches so any raw terminal echo or pasted text residue is cleared back into the bounded MOC Input pane.

v1.13.28 - 2026-06-29
- Fixes MOC Terminal multiline paste handling so pasted script blocks are drained from the console input queue and buffered before the pane redraws.
- Prevents each pasted line from executing separately when the clipboard contains functions, switch blocks, parenthesized calls, or backtick line continuations.
- Keeps pasted multiline command entry contained inside the MOC Input pane while preserving PgUp/PgDn, Up/Down, and Home/End output review.

v1.13.27 - 2026-06-29
- Adds multiline paste support to MOC Terminal so pasted PowerShell blocks are buffered as one command instead of executing one line at a time.
- Uses PowerShell parser completeness checks and paste-buffer detection so Enter only runs the command when the block is ready.
- Updates Terminal guidance/footer semantics to support multiline command entry while keeping output contained in the MOC panes.

v1.13.26 - 2026-06-29
- Fixes MOC Terminal output containment when pasted/free-text commands produce multi-line parser errors, script stack traces, or exception records containing embedded newlines.
- Splits embedded CR/LF output into individual bounded run-console rows before rendering so error text cannot escape the Run Output pane or overwrite pane borders.
- Keeps Terminal mode output reviewable with existing PgUp/PgDn, Up/Down, Home/End navigation while preserving the v1.13.25 ANSI border reset behavior.

v1.13.25 - 2026-06-29
- Refines MOC box rendering so border and divider lines always start from a clean ANSI reset state and render with one explicit pane color end-to-end.
- Adds a dedicated pane-border writer for top, divider, and bottom frame lines to prevent right-edge and corner color bleed from previous text/status coloring.
- Keeps main menu/script activity panes blue and detail/output/input panes light-blue/cyan while eliminating mixed-color corner artifacts.

v1.13.24 - 2026-06-29
- Reworks stacked MOC run-window pane borders so each pane closes and reopens with its own border color instead of sharing mixed-color separator joints.
- Keeps the script/activity pane blue and the output, line-status, and input panes light-blue/cyan with clean left and right edges.
- Prevents pane divider edges from visually inheriting or bleeding into neighboring pane colors during redraws.

v1.13.23 - 2026-06-29
- Updates MOC pane border theming so section borders are consistent by pane type instead of inheriting line text color.
- Uses the primary blue border for menu/script title and progress/activity panes.
- Uses the secondary light-blue/cyan border for details, run-output, output line-status, and input panes.
- Preserves the active scrolling, footer navigation, Terminal mode, and Linux-focused fixes from prior v1.13.x releases.

v1.13.22 - 2026-06-29
- Keeps MOC run/input window borders consistently green even when the line text is rendered in white, gray, yellow, red, cyan, or other status colors.
- Updates panel-line rendering so only the inner message text inherits status coloring while the left and right frame borders retain the standard MOC window color.
- Preserves the active scrolling and footer navigation updates from v1.13.21.

v1.13.21 - 2026-06-29
- Adds active run-console output scrolling while child scripts or MOC Terminal are waiting for input, so PgUp/PgDn, Up/Down, and Home/End can review lengthy output before submitting the next prompt.
- Adds a run-console bottom navigation footer for child scripts and Terminal mode using the standard colon key/action format.
- Moves Terminal command guidance out of the output body and into the footer-style command bar.

v1.13.20 - 2026-06-29
- Fixes Terminal mode launch binding issue where Invoke-MOCTerminal could receive an empty OutputBuffer argument from the command dispatcher and fail before opening the MOC terminal pane.
- Makes Terminal mode output-buffer handling null/empty-string safe while keeping ad-hoc command execution inside the active MOC PowerShell session.
- Preserves T: Terminal command-bar behavior introduced in v1.13.19.

v1.13.19 - 2026-06-29
- Adds T: Terminal from the global MOC command bar for running ad-hoc PowerShell commands inside the active MOC PowerShell session.
- Renders terminal command entry, command output, errors, and completion status inside the existing MOC run/input pane instead of writing below the terminal frame.
- Supports common terminal commands such as Get-MgContext | Format-List *, clear/cls, and exit/back/quit to return to the MOC menu.

v1.13.18 - 2026-06-29
- Updates global MOC footer/navigation command-bar labels to use colon-separated key/action formatting such as Up/Down: Move and Enter: Open Folder for improved readability.
- Applies the same key/action format to Home, folder/script, authentication review, and Module Maintenance footer hints, including compact/narrow-terminal labels.
- Preserves the Linux input-pane and transcript fixes from v1.13.17.

v1.13.17 - 2026-06-29
- Adds a persistent MOC-managed input pane to the child-script run window so interactive prompts remain inside the MOC frame instead of writing to the bottom of the terminal on Linux.
- Updates the parent Read-Host compatibility shim to collect text through the MOC input pane using Console.ReadKey, while preserving fallback-friendly child-script behavior.
- Improves transcript initialization on Linux by avoiding WindowsIdentity-only user lookup, preventing false transcript initialization warnings when the manual transcript file is still created successfully.
- Notes: macOS-specific behavior has not been validated in this release.

v1.13.15 - 2026-06-29
- Fixes Linux crash caused by asynchronous .NET DataReceivedEventHandler callbacks running without a PowerShell runspace during Module Maintenance output capture.
- Replaces async stdout/stderr event handlers with a safer Start-Job/Receive-Job polling model so installer output stays in the MOC run/progress pane without terminating pwsh.
- Preserves the v1.13.14 bounded-pane output behavior and the v1.13.13 Linux CurrentUser/path-space/LastOnlineCheck fixes.
- Notes: macOS-specific behavior has not been validated in this release.

v1.13.14 - 2026-06-29
- Routes Module Maintenance installer output through the bounded MOC run/progress pane instead of allowing installer output to spill into the full terminal on Linux.
- Keeps module install and upgrade operations visible inside the normal MOC status frame, including captured stdout/stderr and completion status.
- Preserves the v1.13.13 Linux fixes for CurrentUser module installation, paths containing spaces, and nullable LastOnlineCheck handling.
- Notes: macOS-specific behavior has not been validated in this release.

v1.13.13 - 2026-06-29
- Improves Linux compatibility for Module Maintenance by defaulting module installer launches to CurrentUser scope instead of AllUsers.
- Fixes Module Maintenance installer launch paths that contain spaces, preventing pwsh from splitting paths such as /home/user/Downloads/MOC v0.1.
- Allows LastOnlineCheck to be empty before the first online module check, preventing null-to-DateTime conversion errors on Linux.
- Updates Module Maintenance launch messaging so normal CurrentUser installs no longer imply an elevated PowerShell window.
- Notes: macOS-specific behavior has not been validated in this release.

v1.13.12 - 2026-06-25
- Adds dynamic -DisableWAM support to parent-owned interactive connection calls when the installed module exposes that parameter.
- Applies -DisableWAM to Azure, Exchange Online, and Purview/Security & Compliance connection attempts without breaking older module versions that do not support the flag.
- Keeps Microsoft Graph using the existing app-only access-token connection path, which does not invoke WAM sign-in.

v1.13.11 - 2026-06-24
- Adds menu-owned Write-MOCOutputLine and Read-MOCMenuChoice helpers for child scripts so multi-line prompts render inside the bounded run-console output pane before input is read.
- Keeps progress/status text separate from child output menus and supports 4/q/Esc cancel choices without printing prompts below the MOC frame.
- Changes the menu exit help to a shorter tip line and uses the progress operation row for compact input guidance.

v1.13.8 - 2026-06-16
- Fixes Windows drive-path detection in Module Maintenance wrapping so backslash paths such as C:\Users are recognized correctly.
- Treats a drive-root path as a path value before rendering, preventing Installer: C followed by :\Users on continuation lines.
- Preserves run-console path wrapping and reserved footer behavior from v1.13.7.

v1.13.7 - 2026-06-16
- Adds shared path-aware wrapping to run-console output so long transcript, session index, report, and file-path lines wrap inside child/auth run panes.
- Wraps metadata label/value paths on continuation lines instead of clipping or spilling past the right pane border.
- Preserves Module Maintenance drive-root wrapping, Ctrl+C state recovery, reserved footer slot, and dynamic pane scaling from v1.13.6.

v1.13.6 - 2026-06-16
- Repairs Module Maintenance installer-path wrapping so Windows drive roots such as C:\ stay with the first path segment instead of splitting as C and :\Users on separate lines.
- If the value area beside the label is too narrow, renders the label on its own line and wraps the full path on aligned continuation lines.
- Preserves path-aware wrapping, Ctrl+C recovery, reserved footer slot, and dynamic pane scaling from v1.13.5.

v1.13.5 - 2026-06-16
- Improves Module Maintenance installer-path wrapping by preferring Windows path separator boundaries instead of splitting immediately after the drive letter.
- Keeps continuation lines aligned under the Installer value and truncates only after the configured maximum wrapped lines.
- Preserves Ctrl+C terminal-state recovery, reserved footer slot, and dynamic pane scaling from v1.13.4.

v1.13.4 - 2026-06-16
- Adds startup terminal-state recovery so MOC resets leftover alternate-screen/frame-buffer state from an abrupt Ctrl+C before entering the UI.
- Wraps the main MOC loop in cleanup/finally handling so Ctrl+C restores the terminal screen/cursor state instead of leaving the next launch with a missing footer.
- Clears and reinitializes the alternate screen buffer on launch to prevent stale soft-redraw state from carrying into the next MOC session.

v1.13.3 - 2026-06-16
- Wraps long Module Maintenance metadata values such as the installer path inside the framed pane instead of letting them spill past the right border.
- Preserves the full installer path across continuation lines when terminal width allows, with safe truncation only after multiple wrapped lines.
- Keeps authentication return-state repair, reserved footer slot, and dynamic pane scaling from v1.13.2.
v1.13.2 - 2026-06-16
- Repairs authentication return state so exiting the auth review pane restores the prior Home/Folder view instead of leaving MOC in AuthReview with zero scripts.
- Keeps the bottom footer frame slot and dynamic pane scaling behavior from v1.13.0/v1.13.1.

v1.13.1 - 2026-06-16
- Adds dynamic vertical layout scaling so Home, script selection, Authentication, and run-console panes expand into available terminal height above the reserved footer.
- Removes the fixed 30-row run-output cap and calculates output viewport height from the visible terminal size.
- Makes details panes stretch to consume unused vertical space while preserving the bottom footer slot.

v1.13.0 - 2026-06-16
- Repairs footer invisibility by reserving the bottom three frame-buffer rows for the navigation footer before each soft redraw completes.
- If content grows too tall, trims overflow above the footer instead of letting the footer render below the visible terminal window.
- Keeps Home, Authentication, Module Maintenance, smart footer, and cursor-hidden behavior from v1.12.9.

v1.12.9 - 2026-06-16
- Repairs footer visibility by anchoring the MOC navigation footer to the bottom of the visible terminal window.
- Adds footer-aware authentication review sizing so the output pane does not push the footer below the screen.
- Adds a safe Write-Footer -NoComplete parameter for framed run/review screens that render a footer as part of the same frame.

v1.12.8 - 2026-06-16
- Repairs the v1.12.7 regression where the Home footer disappeared and pressing A could fall into an empty Authentication folder/script view.
- Keeps authentication in a dedicated run/review screen while it is active, then restores Home cleanly after Enter/Esc/Q.
- Renders authentication navigation once at the bottom of the auth frame and prevents duplicate footer artifacts during PgUp/PgDn review.

v1.12.6 - 2026-06-16
- Restores the normal yellow MOC footer/navigation bar on the authentication completion review pane.
- Adds authentication-specific footer guidance: PgUp/PgDn page, Up/Down scroll, Home/End jump, Enter/Esc return.
- Keeps authentication output review controls from v1.12.5.

v1.12.5 - 2026-06-16
- Fixes authentication completion review controls so PgUp/PgDn scroll authentication output instead of immediately returning to Home.
- Adds authentication-pane review key handling consistent with child-script run output: Enter returns, PgUp/PgDn pages, Up/Down scrolls, Home/End jump.

v1.12.4 - 2026-06-16
- Suppresses Exchange Online Management informational banner/noise, including the REST-based cmdlets message, from leaking outside the MOC TUI.
- Uses quiet Exchange/Purview module import and connection calls while preserving real errors.
- Keeps Module Maintenance hard-clear, adaptive columns, framed install/upgrade actions, smart footer hints, and cursor-hidden behavior.

v1.12.3 - 2026-06-16
- Forces a hard screen reset before Module Maintenance PSGallery progress so the progress pane does not layer under the previous selection screen.
- Keeps adaptive Module Maintenance columns, framed install/upgrade actions, smart footer hints, and cursor-hidden behavior.

v1.12.2 - 2026-06-16
- Adds adaptive Module Maintenance table columns so long module names and version strings remain aligned.
- Truncates overly long table cells with ASCII ellipses when the terminal is narrow instead of letting values run into adjacent columns.

v1.12.1 - 2026-06-16
- Renders Module Maintenance install/upgrade confirmation and launch-result messages inside the standard framed MOC pane with the normal footer below.
- Removes raw Write-Color module-maintenance prompt screens so I/U actions no longer appear outside the MOC window.

v1.12.0 - 2026-06-16
- Reworks Module Maintenance so pressing M immediately renders a progress-driven PSGallery latest-version check, then displays installed vs latest module status.
- Moves Module Maintenance action guidance out of the content pane and into the normal bottom MOC footer.
- Keeps install and upgrade actions explicit while using the standard MOC progress bar during online checks.

v1.11.9 - 2026-06-16
- Fixes Module Maintenance appearing frozen by opening the M pane immediately with installed/baseline module status and moving the PSGallery lookup behind an explicit rendered R refresh action.
- Keeps install/upgrade actions explicit: I installs missing or below-baseline approved modules; U launches approved-module upgrade mode.

v1.11.8 - 2026-06-16
- Keeps the console cursor hidden after MOC frame flushes and menu input waits so the blinking caret no longer appears below the MOC window during normal operation.
- Restores the cursor only when MOC exits or returns control to the normal PowerShell console.

v1.11.7 - 2026-06-16
- Enhances Module Maintenance. M now checks PSGallery for latest approved module versions, shows installed/latest/minimum state, I installs missing/below-baseline components, and U launches an explicit latest-version upgrade flow.
- Keeps child scripts module-validation only; install/update remains a parent MOC maintenance action.

v1.11.5 - 2026-06-15
- Fixes Module Maintenance screen appearing frozen by flushing the buffered MOC frame before waiting for keyboard input.
- Keeps the smart footer hint behavior from v1.11.4.
- Ensures module-installer launch and failure messages are rendered before waiting for Enter.

v1.11.4 - 2026-06-15
- Adds smart responsive footer navigation hints. MOC now keeps essential actions visible first and hides lower-priority hints when the terminal is narrow.
- Prevents footer help text from clipping into partial labels such as "Q Q" by building the footer from prioritized items instead of truncating a single long string.
- Uses compact footer labels on narrow terminals while preserving the high-visibility footer styling.

v1.11.3 - 2026-06-15
- Adds adaptive menu pane height so the home/folder script selection box shrinks to the visible item count instead of padding to the full page size.
- Keeps child-script run-console viewport sizing unchanged so execution output still gets the larger pane.
- Adds configurable minimum menu rows for compact-but-readable folder/script lists.

v1.11.2 - 2026-06-15
- Changes the bottom navigation footer from gray to high-visibility yellow/bold styling so available controls stand out like the completed-status footer.
- Applies the same high-visibility styling to the footer border while keeping ASCII-only labels for stable terminal rendering.

v1.11.1 - 2026-06-15
- Adds semantic color highlighting for MOC run-console output lines. Authentication and child-script output now colors success/connected lines green, active work lines cyan, warnings yellow, errors red, and neutral informational lines white/gray.

v1.11.0 - 2026-06-15
- Renders the A-authentication workflow inside the same framed MOC run-console/progress pane used by child scripts.
- Authentication progress now updates through the bounded progress bar/output pane rather than free-form console lines.
- Authentication failures render inside the MOC pane before returning to the menu.
- Keeps Azure Key Vault warning suppression, alternate screen buffer, responsive layout, symmetric margins, and low-flicker rendering behavior.

v1.10.9 - 2026-06-15
- Fixes authentication screen blanking by flushing the header frame before long-running Azure/Graph/Exchange/Purview authentication calls. Authentication status output now renders immediately inside the dedicated authentication screen instead of staying buffered until completion.
- Keeps Azure Key Vault warning suppression, alternate screen buffer, responsive layout, and low-flicker rendering behavior.

v1.10.8 - 2026-06-15
- Captures/suppresses Azure Key Vault breaking-change warning output during MOC authentication so the authentication pane does not drop into raw terminal output.
- Keeps authentication as a dedicated major screen-mode pane while preserving responsive layout, alternate screen buffer, and symmetric margins.
- Adds explicit MOC-authentication-safe warning handling around Key Vault secret retrieval.

v1.10.7 - 2026-06-15
- Adds a symmetric horizontal content margin so MOC frames are visually balanced left and right.
- Keeps right-edge safety to prevent Windows Terminal auto-wrap while avoiding an obvious one-sided right gap.
- Applies the margin through the buffered renderer so routine navigation remains low flicker.

v1.10.6 - 2026-06-15
- Replaces Unicode arrow footer labels with ASCII-only labels to avoid Windows Terminal cell-width ambiguity.
- Uses a dedicated footer line renderer so the right-side border closes consistently.

v1.10.5 - 2026-06-15
- Fixes footer/menu border rendering by reserving additional terminal columns during frame construction.
- Reduces Windows Terminal auto-wrap side effects that can make right-side box characters appear open or missing.
- Keeps alternate screen buffer behavior so MOC redraw frames do not accumulate in scrollback.

v1.10.4 - 2026-06-15
- Runs the interactive MOC UI inside the terminal alternate screen buffer so routine redraw frames do not accumulate in Windows Terminal scrollback.
- Restores the normal terminal screen buffer when MOC exits or disconnects.
- Keeps per-child transcript logging unchanged, including the one-time MOC ASCII/context snapshot per run.

v1.10.3 - 2026-06-15
- Adds a diff-buffered soft renderer so routine menu navigation writes only changed lines instead of repainting the full frame line-by-line.
- Keeps responsive terminal sizing while reducing flicker during selection movement, refresh, and scroll.
- Uses a one-column-safe render width to avoid terminal auto-wrap and missing right-side border characters.
- Keeps hard clears only for major screen-mode changes such as authentication, quit confirmation, disconnect, and child-run screens.

v1.10.2 - 2026-06-15
- Reduces flicker introduced by responsive layout by debouncing terminal resize detection.
- Keeps dynamic terminal sizing, compact header mode, and minimum-size warning.
- Avoids hard Clear-Host during routine resize/menu redraw cycles; MOC now repositions and repaints in place unless entering a major screen mode.
- Keeps hard clears for major transitions such as authentication, quit confirmation, disconnect, and child-run screens.

v1.10.1 - 2026-06-15
- Adds responsive terminal layout detection for MOC frames and run-console panes.
- Recalculates menu page size, run-console viewport, compact header mode, and minimum-size warnings from the current terminal dimensions.
- Forces a clean redraw only when the terminal size changes, while keeping soft redraw for same-size navigation and scrolling.

v1.10.0 - 2026-06-15
- Renders quit confirmation as an in-frame MOC modal instead of a separate plain confirmation screen.
- Keeps the standard MOC header and footer guidance while confirming quit/disconnect.
- Transitions to a clean MOC disconnect pane after confirmation so disconnect output never overlays the active menu UI.

v1.9.9 - 2026-06-15
- Adds a dedicated quit confirmation screen before disconnecting MOC shared sessions.
- Treats quit/disconnect as a major screen-mode transition and clears the active menu frame before writing disconnect output.
- Press Q, then Y/Enter to disconnect and exit; press N/Esc/Backspace to return to the menu without disconnecting.

v1.9.8 - 2026-06-15
- Adds a lightweight MOC session index log for each menu launch while keeping one transcript per child-script run.
- Session index records child script name, category, status, start/end time, duration, transcript path, and report/output paths where detected.
- Keeps per-child transcript files unchanged and adds a single session-level JSON index under Transcript Logs.

v1.9.7 - 2026-06-15
- Fixes authentication-screen rendering so A-auth output is shown on a dedicated clean authentication screen instead of being written over the active menu/details pane.
- Keeps low-flicker soft redraw for normal navigation and run-console review, but uses a controlled hard clear when switching into the authentication workflow.
- Prevents stale menu panes from remaining behind authentication status messages.

v1.9.6 - 2026-06-15
- Reduces terminal flicker by replacing full Clear-Host redraws with a soft redraw model that homes the cursor, clears each rendered line, and clears leftover lines from prior frames.
- Keeps the bottom footer as the single source of run status/action guidance.
- Reintroduces the MOC ASCII banner/context snapshot into child transcript logs once per run, without mirroring every live redraw frame.

v1.9.5 - 2026-06-15
- Removes the redundant top-of-run Status line from the run-console header.
- Keeps the bottom footer as the single source of truth for run status and available actions.
- Header now identifies only the running script; final state and navigation guidance remain in the footer.

v1.9.4 - 2026-06-15
- Moves completed/failed run-console action guidance to a single footer line at the bottom of the window.
- Removes redundant completed-state instruction text from the header and progress panel.
- Suppresses the redundant "+ Completed successfully" progress status line on completed runs.

v1.9.3 - 2026-06-12
- Refines Microsoft Graph access-token refresh logic. MOC no longer labels generic Graph health-check failures as stale/expired token events.
- Pressing A still force-refreshes Microsoft Graph, but normal child-script startup only refreshes Graph when MOC has a tracked token expiration window.
- Removes the Graph metadata health check that could create false stale-token warnings immediately after authentication.

v1.9.0 - 2026-06-12
- Adds an MOC Module Maintenance action on the M key.
- Module maintenance shows required module health, locates the MOC installer script, and launches it elevated on demand.
- Adds REQUIREDPOWERSHELLMODULES metadata parsing/display so child scripts can declare module prerequisites without installing them during report execution.
- Keeps normal child-script execution read-only with respect to local module installation.

v1.8.9 - 2026-06-12
- Strengthens full shared-session health checks so A-auth validates Graph, Exchange Online, and Purview instead of trusting stale module state.
- Uses live lightweight Exchange and Purview command tests before deciding a service is connected.
- Adds cleaner missing PowerShell module guidance in the run console when a child script requires a module that is not installed.

v1.8.8 - 2026-06-12
- Changes Microsoft Graph app-only authentication to request a Graph access token directly with the MOC app client secret, then connects Graph with -AccessToken.
- Avoids Microsoft.Graph ClientSecretCredential/Azure.Identity/MSAL assembly-version conflicts such as BaseAbstractApplicationBuilder.WithLogging method-not-found errors.
- Keeps Azure Key Vault scoped authentication retry from v1.8.7.

v1.8.7 - 2026-06-12
- Improves MOC parent authentication when Azure Key Vault requires an interactive resource-scoped token.
- If Get-AzKeyVaultSecret reports AzureKeyVaultServiceEndpointResourceId or expired Azure credentials, MOC retries Connect-AzAccount with -AuthScope AzureKeyVaultServiceEndpointResourceId and then retrieves the Graph client secret again.
- Keeps Graph permission guidance on-error only; no recurring permission preflight interruption.

v1.8.6 - 2026-06-11
- Removes the interactive Graph Permission Preflight screen.
- Runs child scripts normally and shows permission guidance only when Microsoft Graph returns a missing-permission or authorization error.
- Keeps REQUIREDGRAPHAPPSCOPES metadata visible in script details for reference without interrupting every run.

v1.8.5 - 2026-06-11
- Added standardized Microsoft Graph missing-permission guidance when a child script throws Authentication_MSGraphPermissionMissing or related Graph authorization errors.
- Kept child authentication menu-owned; permissions are granted in the MOC app registration with tenant admin consent.

v1.8.4 - 2026-06-11
- Keeps transcript logging line/event based only.
- Confirms one parent transcript file is created per child script execution.
- Does not mirror live redraw frames into transcript logs.

v1.8.3 - 2026-06-11
- Stops mirroring every live MOC redraw frame into the transcript log.
- Captures run-console output lines once as they are added to the output buffer.
- Keeps transcript logs readable while preserving child-script output, status, and final result details.

v1.8.2 - 2026-06-10
- Skips blank/whitespace-only child status/transcript messages instead of binding them to -Message.
- Adds extra protection for older child scripts that send blank separator lines.

v1.8.1 - 2026-06-10
- Made menu-owned Write-MOCStatusLine and Write-MOCTranscriptLine explicitly blank-line safe.
- Prevents child-script separator lines from causing empty Message binding errors.

v1.8.0 - 2026-06-10
- Replaced Start-Transcript during child-script runs with an MOC-owned manual transcript writer.
- Prevents file-lock collisions when child scripts write full-path transcript detail.
- Keeps full terminal frame mirroring in Transcript Logs without locking the active log file.

v1.7.9 - 2026-06-10
- Added OUTPUTFORMAT metadata parsing for MOC child scripts.
- Documents XLSX as the standard child-script report output format.

v1.7.8 - 2026-06-10
- Added shared-session health validation before reusing MOC authentication state.
- Sets explicit Graph session state variables for child scripts.
- Reconnects Graph when MOC authenticated flag is true but Get-MgContext is missing or stale.

v1.7.7 - 2026-06-10
- Added REQUIREDGRAPHAPPSCOPES metadata parsing and display for child scripts.
- Menu now surfaces child-script Graph application permission requirements without adding child Connect-* calls.

v1.7.6 - 2026-06-10
- Reverted authentication flow to the last known-good v1.7.2 pattern.
- Removed the auth catch path that treated the Az/Graph blank logging exception as a special interrupted-auth state.
- Ensures failed authentication resets MOC auth state so selecting Auth will prompt again.

v1.7.3 - 2026-06-10
- Added standardized MOC metadata block fields.
- Added Get-MOCScriptMetadata helper for menu and child-script metadata parsing.
- Menu version now derives from comment-based metadata instead of a duplicated literal value.
- Script discovery reads SYNOPSIS, DESCRIPTION, VERSION, AUTHOR, CATEGORY, CREATED, LASTMODIFIED, OUTPUTFORMAT, REQUIREDGRAPHAPPSCOPES, and CHANGELOG from child scripts.

v1.7.2 - 2026-06-09
- Uses root MOC\Reports\<Category>\<TimestampedRunFolder>\ structure.

v1.7.1 - 2026-06-09
- Mirrors MOC terminal frames into parent transcript logs.

v1.7.0 - 2026-06-09
- Adds completion prompt in run-console progress panel.

v1.6.9 - 2026-06-09
- Replaces static environment label with Entra organization display name.

v1.6.8 - 2026-06-09
- Adds transcript-friendly path handling.

v1.6.7 - 2026-06-09
- Adds MOC-owned child-script input prompts.

v1.6.5 - 2026-06-09
- Fixes live redraw append/nesting behavior.

v1.0.0 - 2026-06-08
- Initial MOC menu.
