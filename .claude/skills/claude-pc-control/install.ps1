# Installs the claude-pc-control skill for the current Windows user, so every
# Claude session that runs on this PC can use it.
# Run in PowerShell on the PC:
#   irm https://raw.githubusercontent.com/jharrisberg-lab/ritual-rehearsal/main/.claude/skills/claude-pc-control/install.ps1 | iex
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo = 'jharrisberg-lab/ritual-rehearsal'
$refs = @('main', 'claude/pc-control-automation-skill-vit28r')
$files = @('SKILL.md', 'pcctl.ps1')
$dest = Join-Path $env:USERPROFILE '.claude\skills\claude-pc-control'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$done = $false
foreach ($ref in $refs) {
  try {
    foreach ($f in $files) {
      $url = "https://raw.githubusercontent.com/$repo/$ref/.claude/skills/claude-pc-control/$f"
      Invoke-WebRequest -Uri $url -OutFile (Join-Path $dest $f) -UseBasicParsing
    }
    $done = $true
    Write-Host "Installed claude-pc-control from '$ref' to $dest"
    break
  }
  catch { Write-Host "Not found on '$ref', trying next..." }
}
if (-not $done) { throw 'Install failed: skill files not found on any branch.' }

New-Item -ItemType Directory -Force -Path (Join-Path $env:USERPROFILE '.claude-pc-control\vault') | Out-Null
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'pcctl.ps1') status
