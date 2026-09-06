#Requires -Version 5.1
<#
.SYNOPSIS
    Runs one RiskGuard Strategy Tester scenario (.ini under tests/tester-configs)
    against the VS Capital MT5 terminal and prints the new RiskGuard/Tester log
    lines produced by that run.
.DESCRIPTION
    Test-only tooling; not part of the shipped product. Kills any running
    instance of the terminal bound to the validated data folder first
    (MT5 is single-instance per data folder, so a leftover GUI session
    silently swallows new /config arguments), launches with /config, waits
    for ShutdownTerminal=1 to close it, then diffs the tester agent log.
#>
param(
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = "Stop"

$terminalExe = "C:\Program Files\VS Capital MetaTrader 5 Terminal\terminal64.exe"
$agentLog = "C:\Users\AI\AppData\Roaming\MetaQuotes\Tester\1CC8C1B13933692EC198A5B0EFDA08D7\Agent-127.0.0.1-3000\logs\$(Get-Date -Format 'yyyyMMdd').log"

Get-Process -Name terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

$beforeCount = 0
if(Test-Path $agentLog) {
    $beforeCount = (Get-Content $agentLog -Encoding Unicode -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
}

$proc = Start-Process -FilePath $terminalExe -ArgumentList @("/config:$ConfigPath") -PassThru
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    if(-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { break }
}
Get-Process -Id $proc.Id -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Start-Sleep -Seconds 1
if(-not (Test-Path $agentLog)) {
    Write-Warning "No agent log found at $agentLog"
    exit 1
}
$allLines = Get-Content $agentLog -Encoding Unicode
$newLines = $allLines | Select-Object -Skip $beforeCount
$newLines | Where-Object { $_ -match "RiskGuard|Tester|HARNESS" }
