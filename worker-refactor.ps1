#!/usr/bin/env pwsh
# Refactor Worker Script - PowerShell Version
# ============================================
# Code refactoring and optimization agent

param(
    [string]$Config = "iflow-refactor.yaml",
    [int]$MaxIterations = 100,
    [int]$IterationDelay = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = $SCRIPT_DIR
$LOG_DIR = Join-Path $PROJECT_ROOT "logs"
$SHUTDOWN_FLAG = Join-Path $PROJECT_ROOT "shutdown.flag"
$COMMIT_LOCK = Join-Path $PROJECT_ROOT "commit.lock"
$QUOTA_STATUS = Join-Path $PROJECT_ROOT "quota.status"

$WORKER_NAME = "refactor"
$WORKER_PID = Join-Path $PROJECT_ROOT "worker-$WORKER_NAME.pid"
$WORKER_STATUS = Join-Path $LOG_DIR "worker-$WORKER_NAME-status.txt"
$WORKER_LOG = Join-Path $LOG_DIR "worker-$WORKER_NAME.log"

# Code smell patterns
$CODE_SMELLS = @{
    LongMethod = @{
        Pattern = "function\s+\w+\s*\([^)]*\)\s*\{[^\}]{500,}\}"
        Description = "Method exceeds 500 characters"
        Severity = "medium"
    }
    DuplicateCode = @{
        Pattern = "(\b\w+\s*\([^)]*\)\s*\{[^\}]{50,}\})\1"
        Description = "Duplicate code detected"
        Severity = "high"
    }
    GodClass = @{
        Pattern = "class\s+\w+\s*\{[^\}]{2000,}\}"
        Description = "Class exceeds 2000 characters"
        Severity = "high"
    }
    MagicNumbers = @{
        Pattern = "(?<![""\d])\d{2,}(?![""\d])"
        Description = "Magic numbers found"
        Severity = "low"
    }
    DeepNesting = @{
        Pattern = "(\{[^\}]*\{[^\}]*\{[^\}]*\{)"
        Description = "Deep nesting detected (4+ levels)"
        Severity = "medium"
    }
}

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
# Code Analysis Functions
# =============================================================================

function Find-SourceFiles {
    $extensions = @("*.py", "*.js", "*.ts", "*.jsx", "*.tsx", "*.go", "*.java", "*.cs")
    $files = @()
    
    foreach ($ext in $extensions) {
        $found = Get-ChildItem -Path $PROJECT_ROOT -Filter $ext -Recurse -ErrorAction SilentlyContinue | 
            Where-Object { $_.FullName -notmatch "node_modules|venv|__pycache__|\.git|test" }
        $files += $found
    }
    
    return $files
}

function Measure-FileComplexity {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return 0 }
    
    $complexity = 0
    
    # Count control structures
    $complexity += ([regex]::Matches($content, "\bif\b")).Count
    $complexity += ([regex]::Matches($content, "\belse\b")).Count
    $complexity += ([regex]::Matches($content, "\bfor\b")).Count
    $complexity += ([regex]::Matches($content, "\bwhile\b")).Count
    $complexity += ([regex]::Matches($content, "\bswitch\b")).Count
    $complexity += ([regex]::Matches($content, "\bcase\b")).Count
    $complexity += ([regex]::Matches($content, "\bcatch\b")).Count
    $complexity += ([regex]::Matches($content, "\?")).Count
    
    return $complexity
}

function Find-CodeSmells {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return @() }
    
    $smells = @()
    
    foreach ($smellName in $CODE_SMELLS.Keys) {
        $smell = $CODE_SMELLS[$smellName]
        $matches = [regex]::Matches($content, $smell.Pattern, "IgnoreCase")
        
        if ($matches.Count -gt 0) {
            $smells += @{
                Type = $smellName
                Description = $smell.Description
                Severity = $smell.Severity
                Count = $matches.Count
                File = $FilePath
            }
        }
    }
    
    return $smells
}

function Invoke-CodeAnalysis {
    Write-Log "Running code analysis..."
    
    $files = @(Find-SourceFiles)
    $analysis = @{
        TotalFiles = $files.Count
        HighComplexity = @()
        CodeSmells = @()
    }
    
    foreach ($file in $files) {
        if (Test-ShutdownFlag) { break }
        
        # Check complexity
        $complexity = Measure-FileComplexity -FilePath $file.FullName
        if ($complexity -gt 20) {
            $analysis.HighComplexity += @{
                File = $file.FullName
                Complexity = $complexity
            }
        }
        
        # Check for code smells
        $smells = @(Find-CodeSmells -FilePath $file.FullName)
        if ($smells.Count -gt 0) {
            $analysis.CodeSmells += $smells
        }
    }
    
    return $analysis
}

# =============================================================================
# Refactoring Functions
# =============================================================================

function Invoke-Refactoring {
    param([object]$Analysis)
    
    Write-Log "Processing refactoring opportunities..."
    
    $refactored = 0
    
    # Process high complexity files
    foreach ($file in $Analysis.HighComplexity | Sort-Object Complexity -Descending | Select-Object -First 3) {
        if (Test-ShutdownFlag) { break }
        
        Write-Log "High complexity file: $($file.File) (Complexity: $($file.Complexity))"
        Write-Log "Would suggest extracting methods and reducing nesting"
        $refactored++
    }
    
    # Process code smells
    $highSeveritySmells = $Analysis.CodeSmells | Where-Object { $_.Severity -eq "high" }
    foreach ($smell in $highSeveritySmells | Select-Object -First 5) {
        if (Test-ShutdownFlag) { break }
        
        Write-Log "High severity smell: $($smell.Type) in $($smell.File)"
        Write-Log "Description: $($smell.Description)"
        $refactored++
    }
    
    return $refactored
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
    Write-Log "Starting refactor worker loop..."
    Update-Status "running"
    
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
        
        Update-Status "analyzing"
        $analysis = Invoke-CodeAnalysis
        
        Write-Log "Analysis complete: $($analysis.TotalFiles) files, $($analysis.HighComplexity.Count) high complexity, $($analysis.CodeSmells.Count) code smells"
        
        if ($analysis.HighComplexity.Count -gt 0 -or $analysis.CodeSmells.Count -gt 0) {
            Update-Status "refactoring"
            $refactored = Invoke-Refactoring -Analysis $analysis
            Write-Log "Processed $refactored refactoring opportunities"
            
            $committed = New-GitCommit -Message "Refactoring from iteration $iteration"
            if ($committed) {
                Write-Log "Pushing changes..."
                Sync-GitPush
            }
        }
        
        Update-Status "waiting"
        Start-Sleep -Seconds $IterationDelay
    }
    
    Update-Status "completed"
    Write-Log "Refactor worker completed"
}

# =============================================================================
# Main
# =============================================================================

function Main {
    Write-Log "============================================"
    Write-Log "Refactor Worker Starting"
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
    
    Write-Log "Refactor Worker Exiting"
}

Main
