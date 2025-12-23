# ========================================
# Professional PowerShell Script
# Color-coded for operator clarity
# ========================================

#requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Info([string]$Message) {
  Write-Host "[INFO] [claude-install] $Message" -ForegroundColor White
}

function Refresh-Path {
  $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = @($machinePath, $userPath) -join ';'
}

function Get-NodeVersion {
  $node = Get-Command node -ErrorAction SilentlyContinue
  if (-not $node) { return $null }
  try {
    $raw = & node -v
    if (-not $raw) { return $null }
    return [version]($raw.Trim().TrimStart('v'))
  } catch {
    return $null
  }
}

Write-Info "Starting Claude Code installation..."

if (-not [Environment]::Is64BitOperatingSystem) {
  throw '64-bit Windows is required.'
}

try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
  Write-Info 'Could not set TLS 1.2, continuing with system defaults.'
}

$nodeVersion = Get-NodeVersion
$needsNode = $true
if ($nodeVersion -and $nodeVersion.Major -ge 18) {
  Write-Info "Node.js $nodeVersion detected."
  $needsNode = $false
}

if ($needsNode) {
  Write-Info 'Installing Node.js LTS...'
  $index = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -Method Get
  $lts = $index | Where-Object { $_.lts -ne $false } | Select-Object -First 1
  if (-not $lts) {
    throw 'Failed to locate Node.js LTS build.'
  }
  $ver = $lts.version
  $msiUrl = "https://nodejs.org/dist/$ver/node-$ver-x64.msi"
  $msiPath = Join-Path $env:TEMP "node-$ver-x64.msi"

  Write-Info "Downloading $msiUrl"
  Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath

  Write-Info 'Running Node.js installer...'
  Start-Process msiexec.exe -Wait -ArgumentList @('/i', "`"$msiPath`"", '/qn', '/norestart')
  Remove-Item $msiPath -Force -ErrorAction SilentlyContinue

  Refresh-Path
  $nodeVersion = Get-NodeVersion
  if (-not $nodeVersion) {
    throw 'Node.js did not install correctly.'
  }
  Write-Info "Node.js $nodeVersion installed."
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
  Refresh-Path
}
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
  throw 'npm is not available on PATH.'
}

$npmUserBin = Join-Path $env:APPDATA 'npm'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$npmUserBin*") {
  $newUserPath = if ($userPath) { "$userPath;$npmUserBin" } else { $npmUserBin }
  [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
  Write-Info "Added $npmUserBin to user PATH."
}

Refresh-Path

Write-Info 'Installing Claude Code CLI...'
$oldNativePref = $null
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
  $oldNativePref = $PSNativeCommandUseErrorActionPreference
  $PSNativeCommandUseErrorActionPreference = $false
}
& npm install -g @anthropic-ai/claude-code
$npmExit = $LASTEXITCODE
if ($oldNativePref -ne $null) {
  $PSNativeCommandUseErrorActionPreference = $oldNativePref
}
if ($npmExit -ne 0) {
  throw "npm install failed with exit code $npmExit."
}

Refresh-Path

if (Get-Command claude -ErrorAction SilentlyContinue) {
  $claudeVersion = & claude --version 2>$null
  if ($claudeVersion) {
    Write-Info "Claude installed: $claudeVersion"
  } else {
    Write-Info 'Claude installed.'
  }
  Write-Info 'Open a new admin PowerShell and run: claude'
} else {
  throw 'Claude command not found on PATH.'
}
