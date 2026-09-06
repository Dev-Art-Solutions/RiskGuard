$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repositoryRoot 'src/RiskGuard.mq5'
$requiredFiles = @(
    'README.md',
    'LICENSE',
    'CHANGELOG.md',
    'PORTFOLIO_CASE_STUDY.md',
    'docs/TEST_PLAN.md',
    'docs/RELEASE_NOTES_v1.0.0.md',
    'docs/GITHUB_METADATA.md',
    'docs/validation/README.md',
    'docs/validation/metaeditor-compile.log',
    'docs/validation/demo-state-validation.log',
    'docs/images/riskguard-safe-panel.png',
    'examples/conservative.set',
    'src/RiskGuard.mq5'
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file is missing: $relativePath"
    }
}

$source = Get-Content -Raw -LiteralPath $sourcePath
$requiredSourcePatterns = @(
    'RISK_SAFE',
    'RISK_RESTRICTED',
    'RISK_BLOCKED',
    'RISK_EMERGENCY',
    'OrderCalcProfit',
    'CountEntryOrdersToday',
    'SetTypeFillingBySymbol(symbol)',
    'LIQUIDATION_MAX_BATCHES = 3',
    'LIQUIDATION_RETRY_DELAY_SECONDS = 5',
    'SafeGlobalSet',
    'BASELINE_PERSISTENCE_FAILED',
    'DAILY_LOCK_PERSISTENCE_FAILED',
    'ServerIdentityHash',
    'AccountInfoString(ACCOUNT_SERVER)',
    'INITIAL_STATE',
    'ClosePositionsOnEmergencyStop = false',
    'ClosePositionsOnDailyLossBreach = false',
    'GlobalVariableSet'
)

foreach ($pattern in $requiredSourcePatterns) {
    if (-not $source.Contains($pattern)) {
        throw "Required source behavior was not found: $pattern"
    }
}

$ignore = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot '.gitignore')
if (-not $ignore.Contains('MT5_RISKGUARD_CODEX_PLAN.md')) {
    throw 'The local Codex plan is not excluded by .gitignore.'
}

$trackedPlan = & git -c "safe.directory=$($repositoryRoot -replace '\\','/')" -C $repositoryRoot ls-files -- 'MT5_RISKGUARD_CODEX_PLAN.md'
if ($LASTEXITCODE -ne 0) {
    throw 'git ls-files failed.'
}
if ($trackedPlan) {
    throw 'The local Codex plan is tracked by Git.'
}

Write-Host 'RiskGuard repository validation passed.'
