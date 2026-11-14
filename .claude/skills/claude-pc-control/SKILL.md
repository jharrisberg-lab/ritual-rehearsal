---
name: claude-pc-control
description: Check, change and fix things on the user's Windows PC (DESKTOP-A9F7T6E) directly instead of asking them to do it. Use whenever a step needs the PC - verifying a scheduled task exists or ran, services, processes, startup items, installed apps, files, settings, or saving/using a username and password. Triggers on "check my PC", "is the task created", "on my computer", "save this login", "Claude pc control".
---

# Claude PC Control

Rule one: **never ask the user to check or change something on the PC by hand** (they would have to TeamViewer in from their phone). Do it yourself, then report the result in one or two bullets.

## 1. Get onto the PC

- **Session already running on the PC** (Windows paths, `$env:COMPUTERNAME` is the PC): go to step 2.
- **Cloud session**: call `list_computer_folders`, then `request_computer_folder` for a folder on `DESKTOP-A9F7T6E`. Once attached, commands run on the PC.
- **Cloud session and no folder is offered**: say so in one line and tell the user to open the task in a session on the PC (Claude app on phone -> Remote Control -> pick a PC folder). Do not ask them to check manually and do not invent results.

## 2. Use the helper

Installed at `%USERPROFILE%\.claude\skills\claude-pc-control\pcctl.ps1`. Output is JSON.

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.claude/skills/claude-pc-control/pcctl.ps1" <command> [name]
```

| Need | Command |
|---|---|
| PC summary, am I admin | `status` |
| Does a task exist / did it run | `task-check "<name>"` |
| All non-Microsoft tasks | `task-list` |
| Run / enable / disable a task | `task-run`, `task-enable`, `task-disable "<name>"` |
| Service status | `service <name>` |
| Is a program running | `proc <name>` |
| Startup programs | `startup` |
| Installed apps | `installed [filter]` |

Reading task results: `LastResult` `0x0` = success, `0x41301` = running now, `0x41303` = never run, anything else = failure (look it up, then check the task's action and its log).

If the helper is missing, install it:
`irm https://raw.githubusercontent.com/jharrisberg-lab/ritual-rehearsal/main/.claude/skills/claude-pc-control/install.ps1 | iex`

Anything the helper does not cover: use PowerShell directly (`Get-ScheduledTask`, `Register-ScheduledTask`, `Get-Service`, `Get-WinEvent`, `winget`, registry, files). After every change, re-check and report the verified state.

## 3. Usernames and passwords

Stored in `%USERPROFILE%\.claude-pc-control\vault\`, encrypted with Windows DPAPI - only this Windows user on this PC can decrypt them.

- Save: `pcctl.ps1 cred-set <name> -Username <u> -Password <p>` (omit `-Password` to prompt on the PC).
- List: `cred-list` (names and usernames only).
- Look up: `cred-get <name>`; add `-Reveal` only when the user asks to see the password.
- Delete: `cred-rm <name>` (only when asked).
- Use without printing it:
  ```powershell
  $c = Import-Clixml "$env:USERPROFILE\.claude-pc-control\vault\<name>.xml"   # PSCredential
  # pass $c to -Credential, or $c.GetNetworkCredential().Password to a tool's stdin
  ```

Hard rules:
- Never write a password into a repo, commit, script, scheduled-task argument, log or chat reply. The vault is the only place.
- When the user gives a login in chat, save it straight away and confirm with name + username only.
- Check the vault (`cred-list`) before asking the user for a login.

## 4. When to still ask first

Only for things that are destructive or hard to undo: deleting files/tasks/accounts, uninstalling software, disabling security tools, firewall/registry-wide changes, reboots, anything that spends money. Everything read-only, and routine fixes the user already asked for, just do.

Needs admin and the session is not elevated (`status` -> `IsAdmin: false`): try a per-user alternative first; otherwise say exactly which one command needs an elevated session.
