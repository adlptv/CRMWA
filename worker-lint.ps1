#!/usr/bin/env pwsh
# Lint Worker Script - PowerShell Version
# ========================================
# Code linting and style enforcement agent

param(
    [string]$Config = "iflow-lint.yaml",
    [int]$MaxIterations = 100,
    [int]$IterationDelay = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = $SCRIPT_DIR
$LOG_DIR = Join-Path $PROJECT_ROOT "logs"
$SHUTDOWN_FLAG = Join-Path $PROJECT_ROOT "shutdown.flag"
$COMMIT_LOCK = Join-Path $PROJECT_ROOT "commit.lock"
$QUOTA_STATUS = Join-Path $PROJECT_ROOT "quota.status"

$WORKER_NAME = "lint"
$WORKER_PID = Join-Path $PROJECT_ROOT "worker-$WORKER_NAME.pid"
$WORKER_STATUS = Join-Path $LOG_DIR "worker-$WORKER_NAME-status.txt"
$WORKER_LOG = Join-Path $LOG_DIR "worker-$WORKER_NAME.log"

# =============================================================================
# Logging
# =============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$WORKER_NAME] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARN" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor Cyan }
    }
    
    Add-Content -Path $WORKER_LOG -Value $logMessage
}

# =============================================================================
# State Management
# =============================================================================

function Save-Pid { $PID | Out-File -FilePath $WORKER_PID }
function Update-Status { param([string]$Status); $Status | Out-File -FilePath $WORKER_STATUS }
function Test-ShutdownFlag { return Test-Path $SHUTDOWN_FLAG }
function Test-CommitLock {
    try {
        if (-not (Test-Path $COMMIT_LOCK)) { return $false }
        $content = [System.IO.File]::ReadAllText($COMMIT_LOCK)
        $matches = @{}  # Initialize matches
        if ($content -match "PID=(\d+)") {
            $lockPid = $matches[1]
            $process = Get-Process -Id $lockPid -ErrorAction SilentlyContinue
            if (-not $process) {
                [System.IO.File]::Delete($COMMIT_LOCK)
                return $false
            }
        }
        return $true
    } catch {
        Start-Sleep -Milliseconds 100
        return Test-Path $COMMIT_LOCK
    }
}

function Set-CommitLock {
    $retries = 0
    while ($retries -lt 5) {
        try {
            $content = "PID=$PID`nWORKER=$WORKER_NAME`nTIMESTAMP=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            [System.IO.File]::WriteAllText($COMMIT_LOCK, $content)
            return
        } catch {
            $retries++
            Start-Sleep -Milliseconds 200
        }
    }
}

function Clear-CommitLock {
    try {
        if (Test-Path $COMMIT_LOCK) {
            $content = [System.IO.File]::ReadAllText($COMMIT_LOCK)
            if ($content -match "PID=$PID") {
                [System.IO.File]::Delete($COMMIT_LOCK)
            }
        }
    } catch { }
}

function Set-CommitLock {
    "PID=$PID`nWORKER=$WORKER_NAME`nTIMESTAMP=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $COMMIT_LOCK
}

function Clear-CommitLock {
    if (Test-Path $COMMIT_LOCK) {
        $lockContent = Get-Content $COMMIT_LOCK
        if ($lockContent -match "PID=$PID") { Remove-Item $COMMIT_LOCK -Force }
    }
}

function Get-QuotaPercentage {
    if (-not (Test-Path $QUOTA_STATUS)) { return 100 }
    try {
        $content = Get-Content $QUOTA_STATUS -Raw | ConvertFrom-Json
        return $content.Percentage
    } catch { return 100 }
}

# =============================================================================
# Linter Detection and Execution
# =============================================================================

function Get-LinterConfig {
    param([string]$ProjectType)
    
    $linters = @{
        node = @{
            Linter = "eslint"
            FixCommand = "npx eslint --fix ."
            CheckCommand = "npx eslint ."
            ConfigFiles = @(".eslintrc.js", ".eslintrc.json", ".eslintrc.yaml")
        }
        python = @{
            Linter = "ruff"
            FixCommand = "ruff check --fix ."
            CheckCommand = "ruff check ."
            ConfigFiles = @("ruff.toml", "pyproject.toml")
        }
        typescript = @{
            Linter = "eslint"
            FixCommand = "npx eslint --fix . --ext .ts,.tsx"
            CheckCommand = "npx eslint . --ext .ts,.tsx"
            ConfigFiles = @(".eslintrc.js", ".eslintrc.json")
        }
        go = @{
            Linter = "golint"
            FixCommand = "go fmt ./..."
            CheckCommand = "golint ./..."
            ConfigFiles = @()
        }
        dotnet = @{
            Linter = "dotnet format"
            FixCommand = "dotnet format"
            CheckCommand = "dotnet format --verify-no-changes"
            ConfigFiles = @(".editorconfig")
        }
    }
    
    return $linters[$ProjectType]
}

function Get-ProjectType {
    if (Test-Path "package.json") {
        $packageJson = Get-Content "package.json" -Raw | ConvertFrom-Json
        if ($packageJson.devDependencies.typescript) { return "typescript" }
        return "node"
    }
    if (Test-Path "requirements.txt") { return "python" }
    if (Test-Path "pyproject.toml") { return "python" }
    if (Test-Path "go.mod") { return "go" }
    if (Get-ChildItem -Filter "*.csproj" -ErrorAction SilentlyContinue) { return "dotnet" }
    return "unknown"
}

function Invoke-Linter {
    param(
        [string]$ProjectType,
        [switch]$Fix
    )
    
    $config = Get-LinterConfig -ProjectType $ProjectType
    
    if (-not $config) {
        Write-Log "No linter config for project type: $ProjectType" "WARN"
        return @{ Success = $false; Output = ""; ErrorCount = 0 }
    }
    
    $command = if ($Fix) { $config.FixCommand } else { $config.CheckCommand }
    Write-Log "Running: $command"
    
    try {
        $output = Invoke-Expression $command 2>&1
        $matches = @($output | Select-String -Pattern "error|warning" -CaseSensitive:$false)
        $errorCount = $matches.Count
        
        return @{
            Success = $LASTEXITCODE -eq 0
            Output = $output
            ErrorCount = $errorCount
        }
    } catch {
        Write-Log "Linter execution failed: $_" "ERROR"
        return @{ Success = $false; Output = $_; ErrorCount = 0 }
    }
}

function Invoke-AutoFormat {
    param([string]$ProjectType)
    
    Write-Log "Running auto-formatting..."
    
    switch ($ProjectType) {
        "node" {
            if (Get-Command prettier -ErrorAction SilentlyContinue) {
                Invoke-Expression "npx prettier --write ." 2>&1
            }
        }
        "python" {
            if (Get-Command black -ErrorAction SilentlyContinue) {
                Invoke-Expression "black ." 2>&1
            } elseif (Get-Command ruff -ErrorAction SilentlyContinue) {
                Invoke-Expression "ruff format ." 2>&1
            }
        }
        "go" {
            Invoke-Expression "go fmt ./..." 2>&1
        }
    }
}

# =============================================================================
# Git Operations
# =============================================================================

function New-GitCommit {
    param([string]$Message)
    
    $quota = Get-QuotaPercentage
    if ($quota -lt 10) { return $false }
    
    $waitCount = 0
    while (Test-CommitLock -and $waitCount -lt 30) {
        Start-Sleep -Seconds 1; $waitCount++
    }
    
    if (Test-CommitLock) { return $false }
    
    Set-CommitLock
    
    try {
        git add -A
        git commit -m "[$WORKER_NAME] $Message"
        Write-Log "Committed: $Message" "SUCCESS"
        return $true
    } catch {
        Write-Log "Commit failed: $_" "ERROR"
        return $false
    } finally {
        Clear-CommitLock
    }
}

function Sync-GitPull {
    param([string]$Branch = "ai-dev")
    
    try {
        git checkout -- "commit.lock" "*.pid" 2>$null
        git pull origin $Branch 2>&1 | Out-Null
        Write-Log "Pulled from origin/$Branch" "SUCCESS"
        return $true
    } catch {
        Write-Log "Pull failed: $_" "WARN"
        return $true
    }
}

function Sync-GitPush {
    param([string]$Branch = "ai-dev")
    
    try {
        git push origin $Branch 2>&1 | Out-Null
        Write-Log "Pushed to origin/$Branch" "SUCCESS"
        return $true
    } catch {
        Write-Log "Push failed: $_" "WARN"
        return $true
    }
}

# =============================================================================
# Main Worker Loop
# =============================================================================

function Invoke-WorkerLoop {
    Write-Log "Starting lint worker loop..."
    Update-Status "running"
    
    $projectType = Get-ProjectType
    Write-Log "Detected project type: $projectType"
    
    $iteration = 0
    
    while ($iteration -lt $MaxIterations) {
        $iteration++
        Write-Log "=== Iteration $iteration/$MaxIterations ==="
        
        if (Test-ShutdownFlag) {
            Write-Log "Shutdown detected, exiting" "WARN"
            Update-Status "shutdown"
            return
        }
        
        $quota = Get-QuotaPercentage
        if ($quota -lt 10) {
            Write-Log "Quota critical, pausing..." "WARN"
            Start-Sleep -Seconds 60
            continue
        }
        
        # Pull latest changes
        Write-Log "Pulling latest changes..."
        Sync-GitPull
        
        Update-Status "checking"
        
        # Run linter check
        $result = Invoke-Linter -ProjectType $projectType
        
        Write-Log "Linter result: $($result.ErrorCount) issues found"
        
        if ($result.ErrorCount -gt 0) {
            Update-Status "fixing"
            
            # Auto-fix issues
            Invoke-Linter -ProjectType $projectType -Fix
            Invoke-AutoFormat -ProjectType $projectType
            
            # Re-run check
            $verifyResult = Invoke-Linter -ProjectType $projectType
            Write-Log "After fix: $($verifyResult.ErrorCount) issues remaining"
            
            $committed = New-GitCommit -Message "Lint fixes from iteration $iteration"
            if ($committed) {
                Write-Log "Pushing changes..."
                Sync-GitPush
            }
        }
        
        Update-Status "waiting"
        Start-Sleep -Seconds $IterationDelay
    }
    
    Update-Status "completed"
    Write-Log "Lint worker completed"
}

# =============================================================================
# Main
# =============================================================================

function Main {
    Write-Log "============================================"
    Write-Log "Lint Worker Starting"
    Write-Log "============================================"
    Write-Log "PID: $PID"
    
    if (-not (Test-Path $LOG_DIR)) {
        New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
    }
    
    Save-Pid
    Update-Status "initializing"
    
    try {
        Invoke-WorkerLoop
    } catch {
        Write-Log "Worker error: $_" "ERROR"
        Update-Status "error"
    }
    
    Write-Log "Lint Worker Exiting"
}

Main
