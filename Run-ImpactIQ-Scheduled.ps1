<#
.SYNOPSIS
    Scheduled/non-interactive runner for ImpactIQ.

.DESCRIPTION
    Edit the settings in the CONFIGURATION section below, then point Windows Task
    Scheduler at this file. The wrapper keeps the Config folder beside the output
    folder, runs the main ImpactIQ script without picker dialogs, writes a log,
    and deletes bulky Report Backups after metadata extraction by default.
#>

param(
    [string]$BaseFolderPath = $PSScriptRoot,
    [ValidateSet('Public', 'Germany', 'USGov', 'China', 'USGovHigh', 'USGovMil')]
    [string]$LoginEnvironment = 'Public',
    [ValidateSet('Workspaces', 'Reports')]
    [string]$RunMode = 'Workspaces',
    [string[]]$WorkspaceIds = @(),
    [string[]]$ReportIds = @(),
    [bool]$AllWorkspaces = $true,
    [bool]$IncludeMyWorkspace = $false,
    [switch]$KeepReportBackups
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================
# CONFIGURATION
# =============================
# The defaults above are deliberately scheduler-friendly:
# - BaseFolderPath defaults to the folder containing this wrapper. Put this repo
#   wherever you want the ImpactIQ outputs generated, or pass -BaseFolderPath.
# - Workspaces mode defaults to all accessible workspaces.
# - My Workspace is excluded by default to avoid personal/report noise.
# - Report Backups are deleted after extraction unless -KeepReportBackups is set.
#
# Examples:
#   .\Run-ImpactIQ-Scheduled.ps1 -BaseFolderPath 'D:\PowerBI\ImpactIQ'
#   .\Run-ImpactIQ-Scheduled.ps1 -WorkspaceIds @('workspace-guid-1','workspace-guid-2')
#   .\Run-ImpactIQ-Scheduled.ps1 -RunMode Reports -ReportIds @('report-guid-1')

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseFolderPath = [System.IO.Path]::GetFullPath($BaseFolderPath)

if (-not (Test-Path -Path $BaseFolderPath)) {
    New-Item -Path $BaseFolderPath -ItemType Directory -Force | Out-Null
}

# Keep runtime dependencies available in the output folder because the main script
# resolves Config relative to -BaseFolderPath.
$sourceConfig = Join-Path -Path $scriptRoot -ChildPath 'Config'
$targetConfig = Join-Path -Path $BaseFolderPath -ChildPath 'Config'
if (-not (Test-Path -Path $sourceConfig)) {
    throw "Config folder not found beside scheduled runner: $sourceConfig"
}
if ([System.IO.Path]::GetFullPath($sourceConfig).TrimEnd('\\') -ne [System.IO.Path]::GetFullPath($targetConfig).TrimEnd('\\')) {
    Copy-Item -Path $sourceConfig -Destination $BaseFolderPath -Recurse -Force
}

$sourcePbit = Join-Path -Path $scriptRoot -ChildPath 'Power BI Governance Model.pbit'
if ((Test-Path -Path $sourcePbit) -and ([System.IO.Path]::GetFullPath($scriptRoot).TrimEnd('\\') -ne $BaseFolderPath.TrimEnd('\\'))) {
    Copy-Item -Path $sourcePbit -Destination $BaseFolderPath -Force
}

# PowerShell script files should use .ps1 for Task Scheduler. The upstream file is
# kept as .txt for copy/paste compatibility, so copy it to a generated .ps1 at run time.
$sourceScript = Join-Path -Path $scriptRoot -ChildPath 'Final PS Script.txt'
if (-not (Test-Path -Path $sourceScript)) {
    throw "Main ImpactIQ script not found: $sourceScript"
}
$scheduledScript = Join-Path -Path $BaseFolderPath -ChildPath 'Final PS Script.scheduled.ps1'
Copy-Item -Path $sourceScript -Destination $scheduledScript -Force

$logsFolder = Join-Path -Path $BaseFolderPath -ChildPath 'Logs'
if (-not (Test-Path -Path $logsFolder)) {
    New-Item -Path $logsFolder -ItemType Directory -Force | Out-Null
}
$logPath = Join-Path -Path $logsFolder -ChildPath ("ImpactIQ-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

$scriptArgs = @(
    '-BaseFolderPath', $BaseFolderPath,
    '-LoginEnvironment', $LoginEnvironment,
    '-RunMode', $RunMode,
    '-NonInteractive'
)

if ($RunMode -eq 'Workspaces') {
    if ($WorkspaceIds.Count -gt 0) {
        $scriptArgs += '-WorkspaceIds'
        $scriptArgs += $WorkspaceIds
    }
    elseif ($AllWorkspaces) {
        $scriptArgs += '-AllWorkspaces'
    }
    else {
        throw "Workspaces mode needs either -WorkspaceIds or -AllWorkspaces `$true."
    }

    if ($IncludeMyWorkspace) {
        $scriptArgs += '-IncludeMyWorkspace'
    }
}
else {
    if ($ReportIds.Count -eq 0) {
        throw "Reports mode needs -ReportIds."
    }
    $scriptArgs += '-ReportIds'
    $scriptArgs += $ReportIds

    if ($WorkspaceIds.Count -gt 0) {
        $scriptArgs += '-WorkspaceIds'
        $scriptArgs += $WorkspaceIds
    }
}

if (-not $KeepReportBackups) {
    $scriptArgs += '-DeleteReportBackupsAfterExtraction'
}

Write-Host "[INFO] Starting ImpactIQ scheduled run. Log: $logPath"
Start-Transcript -Path $logPath -Append | Out-Null
try {
    & $scheduledScript @scriptArgs
}
finally {
    Stop-Transcript | Out-Null
}
