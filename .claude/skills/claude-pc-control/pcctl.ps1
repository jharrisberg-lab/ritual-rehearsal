# pcctl.ps1 - Claude PC Control helper (Windows PowerShell 5.1+).
# Output is JSON so Claude can read it reliably.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File pcctl.ps1 <command> [name] [options]
param(
  [Parameter(Position = 0)][string]$Command = 'help',
  [Parameter(Position = 1)][string]$Name,
  [string]$Username,
  [string]$Password,
  [switch]$Reveal
)

$ErrorActionPreference = 'Stop'
$VaultDir = Join-Path $env:USERPROFILE '.claude-pc-control\vault'

function Out-J($o) {
  if ($null -eq $o) { '[]' } else { ConvertTo-Json -InputObject @($o) -Depth 5 }
}

function Need-Name {
  if (-not $Name) { throw "Command '$Command' needs a name argument." }
}

function Find-Tasks($pattern) {
  # Exact name first, then wildcard match.
  $all = Get-ScheduledTask
  $hit = @($all | Where-Object { $_.TaskName -eq $pattern })
  if ($hit.Count -eq 0) { $hit = @($all | Where-Object { $_.TaskName -like "*$pattern*" }) }
  $hit
}

function Task-Report($tasks) {
  foreach ($t in $tasks) {
    $i = $t | Get-ScheduledTaskInfo
    [pscustomobject]@{
      Name           = $t.TaskName
      Path           = $t.TaskPath
      State          = "$($t.State)"
      RunAs          = $t.Principal.UserId
      Actions        = @($t.Actions | ForEach-Object { ("$($_.Execute) $($_.Arguments)").Trim() })
      Triggers       = @($t.Triggers | ForEach-Object { $_.CimClass.CimClassName -replace '^MSFT_Task', '' -replace 'Trigger$', '' })
      LastRun        = "$($i.LastRunTime)"
      LastResult     = ('0x{0:X}' -f $i.LastTaskResult)
      NextRun        = "$($i.NextRunTime)"
      MissedRuns     = $i.NumberOfMissedRuns
    }
  }
}

function Cred-Path($n) {
  $safe = $n -replace '[^A-Za-z0-9._-]', '_'
  Join-Path $VaultDir "$safe.xml"
}

switch ($Command.ToLower()) {

  'status' {
    $os = Get-CimInstance Win32_OperatingSystem
    Out-J ([pscustomobject]@{
        Computer   = $env:COMPUTERNAME
        User       = $env:USERNAME
        OS         = $os.Caption
        Build      = $os.BuildNumber
        LastBoot   = "$($os.LastBootUpTime)"
        FreeRamGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        TotalRamGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        Disks      = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
            [pscustomobject]@{ Drive = $_.DeviceID; FreeGB = [math]::Round($_.FreeSpace / 1GB, 1); SizeGB = [math]::Round($_.Size / 1GB, 1) }
          })
        IsAdmin    = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
      })
  }

  # ---- Scheduled tasks ----
  'task-check' {
    Need-Name
    $t = @(Find-Tasks $Name)
    if ($t.Count -eq 0) { Out-J ([pscustomobject]@{ Exists = $false; Query = $Name }) }
    else { Out-J (Task-Report $t) }
  }
  'task-list' {
    # Non-Microsoft tasks only, unless a name filter is given.
    if ($Name) { $t = @(Find-Tasks $Name) }
    else { $t = @(Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' }) }
    Out-J (Task-Report $t)
  }
  'task-run' { Need-Name; Find-Tasks $Name | Start-ScheduledTask; Start-Sleep 2; Out-J (Task-Report (Find-Tasks $Name)) }
  'task-enable' { Need-Name; Find-Tasks $Name | Enable-ScheduledTask | Out-Null; Out-J (Task-Report (Find-Tasks $Name)) }
  'task-disable' { Need-Name; Find-Tasks $Name | Disable-ScheduledTask | Out-Null; Out-J (Task-Report (Find-Tasks $Name)) }

  # ---- Services / processes / startup ----
  'service' {
    Need-Name
    Out-J (Get-Service -Name "*$Name*" -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, @{n = 'Status'; e = { "$($_.Status)" } }, @{n = 'StartType'; e = { "$($_.StartType)" } })
  }
  'proc' {
    Need-Name
    Out-J (Get-Process -Name "*$Name*" -ErrorAction SilentlyContinue | Select-Object Name, Id, @{n = 'MemMB'; e = { [math]::Round($_.WorkingSet64 / 1MB) } }, @{n = 'Started'; e = { "$($_.StartTime)" } }, Path)
  }
  'startup' {
    Out-J (Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User)
  }
  'installed' {
    $keys = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $apps = Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
    if ($Name) { $apps = $apps | Where-Object { $_.DisplayName -like "*$Name*" } }
    Out-J ($apps | Sort-Object DisplayName | Select-Object DisplayName, DisplayVersion, Publisher)
  }

  # ---- Credential vault (DPAPI: only this Windows user on this PC can decrypt) ----
  'cred-set' {
    Need-Name
    if (-not $Username) { throw 'cred-set needs -Username.' }
    if ($Password) { $sec = ConvertTo-SecureString $Password -AsPlainText -Force }
    else { $sec = Read-Host "Password for $Name ($Username)" -AsSecureString }
    New-Item -ItemType Directory -Force -Path $VaultDir | Out-Null
    (New-Object System.Management.Automation.PSCredential($Username, $sec)) | Export-Clixml -Path (Cred-Path $Name)
    Out-J ([pscustomobject]@{ Saved = $Name; Username = $Username })
  }
  'cred-get' {
    Need-Name
    $p = Cred-Path $Name
    if (-not (Test-Path $p)) { Out-J ([pscustomobject]@{ Exists = $false; Name = $Name }); break }
    $c = Import-Clixml -Path $p
    $o = [ordered]@{ Name = $Name; Username = $c.UserName; File = $p }
    if ($Reveal) { $o.Password = $c.GetNetworkCredential().Password }
    Out-J ([pscustomobject]$o)
  }
  'cred-list' {
    if (-not (Test-Path $VaultDir)) { Out-J $null; break }
    Out-J (Get-ChildItem $VaultDir -Filter *.xml | ForEach-Object {
        [pscustomobject]@{ Name = $_.BaseName; Username = (Import-Clixml $_.FullName).UserName; Updated = "$($_.LastWriteTime)" }
      })
  }
  'cred-rm' {
    Need-Name
    $p = Cred-Path $Name
    $existed = Test-Path $p
    if ($existed) { Remove-Item $p -Force }
    Out-J ([pscustomobject]@{ Removed = $existed; Name = $Name })
  }

  default {
    @'
pcctl.ps1 <command> [name] [options]
  status                       PC summary (OS, RAM, disks, admin?)
  task-check <name>            Does a scheduled task exist? state, last/next run, result
  task-list [filter]           Non-Microsoft scheduled tasks (or filtered)
  task-run|task-enable|task-disable <name>
  service <name>               Service status
  proc <name>                  Running processes
  startup                      Startup programs
  installed [filter]           Installed apps
  cred-set <name> -Username u [-Password p]   Save login (prompts if no -Password)
  cred-get <name> [-Reveal]    Username (password only with -Reveal)
  cred-list                    Saved logins (names + usernames only)
  cred-rm <name>               Delete a saved login
'@
  }
}
