#!/usr/bin/env pwsh
# Coverage Worker Script - PowerShell Version
# ============================================
# Test coverage analysis and improvement agent

param(
    [string]$Config = "iflow-coverage.yaml",
    [int]$MaxIterations = 100,
    [int]$IterationDelay = 30,
    [int]$TargetCoverage = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = $SCRIPT_DIR
$LOG_DIR = Join-Path $PROJECT_ROOT "logs"
$SHUTDOWN_FLAG = Join-Path $PROJECT_ROOT "shutdown.flag"
$COMMIT_LOCK = Join-Path $PROJECT_ROOT "commit.lock"
$QUOTA_STATUS = Join-Path $PROJECT_ROOT "quota.status"

$WORKER_NAME = "coverage"
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
# Coverage Analysis Functions
# =============================================================================

function Get-ProjectType {
    if (Test-Path "package.json") { return "node" }
    if (Test-Path "requirements.txt") { return "python" }
    if (Test-Path "go.mod") { return "go" }
    if (Test-Path "pom.xml") { return "java" }
    if (Test-Path "*.csproj") { return "dotnet" }
    return "unknown"
}

function Invoke-CoverageAnalysis {
    param([string]$ProjectType)
    
    Write-Log "Running coverage analysis for $ProjectType project..."
    
    $coverageResult = @{
        Lines = 0
        Functions = 0
        Branches = 0
        Total = 0
        Report = ""
    }
    
    switch ($ProjectType) {
        "node" {
            # Check for coverage tools
            if (Test-Path "jest.config.js") {
                $result = npm run coverage 2>&1
                $coverageResult.Report = $result
            } elseif (Test-Path "package.json") {
                $packageJson = Get-Content "package.json" -Raw | ConvertFrom-Json
                if ($packageJson.scripts.cover) {
                    $result = npm run cover 2>&1
                    $coverageResult.Report = $result
                }
            }
        }
        "python" {
            if (Get-Command pytest -ErrorAction SilentlyContinue) {
                $result = pytest --cov=. --cov-report=term 2>&1
                $coverageResult.Report = $result
                
                # Parse coverage percentage
                if ($result -match "TOTAL\s+\d+\s+\d+\s+(\d+)%") {
                    $coverageResult.Total = [int]$matches[1]
                }
            }
        }
        "go" {
            $result = go test -cover ./... 2>&1
            $coverageResult.Report = $result
        }
        "dotnet" {
            $result = dotnet test --collect:"XPlat Code Coverage" 2>&1
            $coverageResult.Report = $result
        }
    }
    
    return $coverageResult
}

function Find-UncoveredFiles {
    param([object]$CoverageResult)
    
    $uncovered = @()
    
    # Parse coverage report for uncovered files
    if ($CoverageResult.Report) {
        $lines = $CoverageResult.Report -split "`n"
        foreach ($line in $lines) {
            if ($line -match "^(\S+)\s+\d+\s+\d+\s+(\d+)%") {
                $file = $matches[1]
                $coverage = [int]$matches[2]
                if ($coverage -lt $TargetCoverage) {
                    $uncovered += @{
                        File = $file
                        Coverage = $coverage
                    }
                }
            }
        }
    }
    
    return $uncovered
}

function New-TestFile {
    param(
        [string]$SourceFile,
        [string]$ProjectType
    )
    
    $testFile = ""
    
    switch ($ProjectType) {
        "node" {
            $testFile = $SourceFile -replace "\.js$", ".test.js"
            $testFile = $testFile -replace "\.ts$", ".test.ts"
        }
        "python" {
            $testFile = $SourceFile -replace "\.py$", "_test.py"
            $testFile = $testFile -replace "^(.+)/([^/]+)$", "tests/$2"
        }
        "go" {
            $testFile = $SourceFile -replace "\.go$", "_test.go"
        }
    }
    
    return $testFile
}

# =============================================================================
# Git Operations
# =============================================================================

function New-GitCommit {
    param([string]$Message)
    
    $quota = Get-QuotaPercentage
    if ($quota -lt 10) {
        Write-Log "Quota critical, skipping commit" "WARN"
        return $false
    }
    
    $waitCount = 0
    while (Test-CommitLock -and $waitCount -lt 30) {
        Start-Sleep -Seconds 1
        $waitCount++
    }
    
    if (Test-CommitLock) {
        Write-Log "Commit lock held, skipping" "WARN"
        return $false
    }
    
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
    
    $quota = Get-QuotaPercentage
    if ($quota -lt 10) { return $false }
    
    $waitCount = 0
    while (Test-CommitLock -and $waitCount -lt 30) { Start-Sleep -Seconds 1; $waitCount++ }
    if (Test-CommitLock) { return $false }
    
    Set-CommitLock
    try {
        git fetch origin
        $remoteBranch = git branch -r --list "origin/$Branch"
        if (-not $remoteBranch) { return $true }
        
        $hasChanges = git status --porcelain
        if ($hasChanges) { git stash push -m "Auto-stash by $WORKER_NAME" }
        git pull --rebase origin $Branch
        if ($hasChanges) { git stash pop }
        
        Write-Log "Pulled from origin/$Branch" "SUCCESS"
        return $true
    } catch {
        Write-Log "Pull failed: $_" "ERROR"
        return $false
    } finally {
        Clear-CommitLock
    }
}

function Sync-GitPush {
    param([string]$Branch = "ai-dev")
    
    $quota = Get-QuotaPercentage
    if ($quota -lt 10) { return $false }
    
    $waitCount = 0
    while (Test-CommitLock -and $waitCount -lt 30) { Start-Sleep -Seconds 1; $waitCount++ }
    if (Test-CommitLock) { return $false }
    
    Set-CommitLock
    try {
        $output = git push origin $Branch 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Pushed to origin/$Branch" "SUCCESS"
            return $true
        }
        $output2 = git push -u origin $Branch 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Pushed and set upstream" "SUCCESS"
            return $true
        }
        return $false
    } catch {
        Write-Log "Push failed: $_" "ERROR"
        return $false
    } finally {
        Clear-CommitLock
    }
}

# =============================================================================
# Main Worker Loop
# =============================================================================

function Invoke-WorkerLoop {
    Write-Log "Starting coverage worker loop..."
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
            Write-Log "Quota critical ($quota%), pausing..." "WARN"
            Start-Sleep -Seconds 60
            continue
        }
        
        # Pull latest changes
        Write-Log "Pulling latest changes..."
        Sync-GitPull
        
        Update-Status "analyzing"
        
        # Run coverage analysis
        $coverage = Invoke-CoverageAnalysis -ProjectType $projectType
        Write-Log "Current coverage: $($coverage.Total)%"
        
        # Check if target met
        if ($coverage.Total -ge $TargetCoverage) {
            Write-Log "Target coverage ($TargetCoverage%) achieved!" "SUCCESS"
            Update-Status "target_met"
            break
        }
        
        # Find uncovered files
        Update-Status "generating"
        $uncovered = @(Find-UncoveredFiles -CoverageResult $coverage)
        Write-Log "Found $($uncovered.Count) files below target coverage"
        
        # Generate tests for uncovered files
        foreach ($file in $uncovered | Select-Object -First 5) {
            if (Test-ShutdownFlag) { break }
            
            Write-Log "Generating tests for: $($file.File) ($($file.Coverage)% coverage)"
            
            $testFile = New-TestFile -SourceFile $file.File -ProjectType $projectType
            if ($testFile) {
                # Here we would invoke iFlow to generate tests
                Write-Log "Test file would be: $testFile"
            }
        }
        
        $committed = New-GitCommit -Message "Coverage improvements from iteration $iteration"
        if ($committed) {
            Write-Log "Pushing changes..."
            Sync-GitPush
        }
        
        Update-Status "waiting"
        Start-Sleep -Seconds $IterationDelay
    }
    
    Update-Status "completed"
    Write-Log "Coverage worker completed"
}

# =============================================================================
# Main
# =============================================================================

function Main {
    Write-Log "============================================"
    Write-Log "Coverage Worker Starting"
    Write-Log "============================================"
    Write-Log "PID: $PID"
    Write-Log "Target Coverage: $TargetCoverage%"
    
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
    
    Write-Log "Coverage Worker Exiting"
}

Main
