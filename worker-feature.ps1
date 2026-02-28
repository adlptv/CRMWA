#!/usr/bin/env pwsh
# Feature Worker Script - PowerShell Version
# ============================================
# Automated feature implementation agent

param(
    [string]$Config = "iflow-feature.yaml",
    [int]$MaxIterations = 100,
    [int]$IterationDelay = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = $SCRIPT_DIR
$LOG_DIR = Join-Path $PROJECT_ROOT "logs"
$CONFIG_FILE = Join-Path $PROJECT_ROOT $Config
$SHUTDOWN_FLAG = Join-Path $PROJECT_ROOT "shutdown.flag"
$COMMIT_LOCK = Join-Path $PROJECT_ROOT "commit.lock"
$QUOTA_STATUS = Join-Path $PROJECT_ROOT "quota.status"
$FEATURE_QUEUE = Join-Path $PROJECT_ROOT "feature-queue.json"
$FEATURE_DONE = Join-Path $PROJECT_ROOT "feature-done.json"

$WORKER_NAME = "feature"
$WORKER_PID = Join-Path $PROJECT_ROOT "worker-$WORKER_NAME.pid"
$WORKER_STATUS = Join-Path $LOG_DIR "worker-$WORKER_NAME-status.txt"
$WORKER_LOG = Join-Path $LOG_DIR "worker-$WORKER_NAME.log"

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
# Feature Management
# =============================================================================

function Get-FeatureQueue {
    if (-not (Test-Path $FEATURE_QUEUE)) {
        return @()
    }
    try {
        $content = Get-Content $FEATURE_QUEUE -Raw | ConvertFrom-Json
        return $content
    } catch { return @() }
}

function Save-FeatureQueue {
    param([array]$Queue)
    $Queue | ConvertTo-Json -Depth 10 | Out-File -FilePath $FEATURE_QUEUE
}

function Get-CompletedFeatures {
    if (-not (Test-Path $FEATURE_DONE)) { return @() }
    try {
        return Get-Content $FEATURE_DONE -Raw | ConvertFrom-Json
    } catch { return @() }
}

function Save-CompletedFeature {
    param([object]$Feature)
    $done = @(Get-CompletedFeatures)
    $done += $Feature
    $done | ConvertTo-Json -Depth 10 | Out-File -FilePath $FEATURE_DONE
}

function Get-NextFeature {
    $queue = @(Get-FeatureQueue)
    if ($queue.Count -eq 0) { return $null }
    return $queue[0]
}

function Remove-FeatureFromQueue {
    $queue = @(Get-FeatureQueue)
    if ($queue.Count -gt 0) {
        $queue = $queue | Select-Object -Skip 1
        Save-FeatureQueue -Queue $queue
    }
}

function Find-SourceFiles {
    $extensions = @("*.ts", "*.tsx", "*.js", "*.jsx", "*.py", "*.go", "*.java", "*.cs")
    $files = @()
    
    foreach ($ext in $extensions) {
        $found = Get-ChildItem -Path $PROJECT_ROOT -Filter $ext -Recurse -ErrorAction SilentlyContinue | 
                 Where-Object { $_.FullName -notmatch "node_modules|venv|__pycache__|\.git|dist|build" }
        $files += $found
    }
    
    return $files
}

function Get-ProjectStructure {
    $structure = @{
        Directories = @()
        MainFiles = @()
        ConfigFiles = @()
    }
    
    # Get directories
    $dirs = Get-ChildItem -Path $PROJECT_ROOT -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch "node_modules|venv|__pycache__|\.git|dist|build|logs" }
    $structure.Directories = $dirs | ForEach-Object { $_.Name }
    
    # Get main files
    $mainFiles = Get-ChildItem -Path $PROJECT_ROOT -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match "^(index|main|app|server)" }
    $structure.MainFiles = $mainFiles | ForEach-Object { $_.Name }
    
    # Get config files
    $configFiles = Get-ChildItem -Path $PROJECT_ROOT -Filter "*.json" -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match "package|tsconfig|config" }
    $structure.ConfigFiles = $configFiles | ForEach-Object { $_.Name }
    
    return $structure
}

function Get-CodebaseContext {
    $context = @{
        Structure = Get-ProjectStructure
        FileCount = @(Find-SourceFiles).Count
        Languages = @()
    }
    
    # Detect languages
    if (Test-Path "package.json") { $context.Languages += "JavaScript/TypeScript" }
    if ((Test-Path "requirements.txt") -or @(Get-ChildItem -Filter "*.py" -ErrorAction SilentlyContinue).Count -gt 0) { 
        $context.Languages += "Python" 
    }
    if (Get-ChildItem -Filter "*.go" -ErrorAction SilentlyContinue) { $context.Languages += "Go" }
    
    return $context
}

function Invoke-iFlowAgent {
    param(
        [string]$Prompt,
        [string]$Mode = "thinking"
    )
    
    Write-Log "Invoking iFlow agent with mode: $Mode"
    
    try {
        # Create temp file for prompt
        $promptFile = Join-Path $env:TEMP "iflow-prompt-$(Get-Random).txt"
        $Prompt | Out-File -FilePath $promptFile -Encoding UTF8
        
        # Call iFlow CLI
        $result = & iflow --mode $Mode --file $promptFile 2>&1
        
        # Cleanup
        Remove-Item $promptFile -Force -ErrorAction SilentlyContinue
        
        return $result
    } catch {
        Write-Log "iFlow invocation failed: $_" "ERROR"
        return $null
    }
}

function Implement-Feature {
    param([object]$Feature)
    
    Write-Log "Implementing feature: $($Feature.Name)"
    
    # Get codebase context
    $context = Get-CodebaseContext
    
    # Build implementation prompt
    $prompt = @"
You are implementing a new feature for a codebase.

FEATURE REQUEST:
Name: $($Feature.Name)
Description: $($Feature.Description)
Priority: $($Feature.Priority)
Category: $($Feature.Category)

CODEBASE CONTEXT:
Languages: $($context.Languages -join ', ')
Total Files: $($context.FileCount)
Directories: $($context.Directories -join ', ')
Main Files: $($context.MainFiles -join ', ')

REQUIREMENTS:
1. Analyze the existing codebase structure
2. Implement the feature following existing patterns
3. Create any necessary new files
4. Update existing files if needed
5. Add appropriate error handling
6. Follow the project's coding conventions

Please provide:
1. List of files to create/modify
2. Complete code for each file
3. Brief explanation of implementation
"@
    
    $result = Invoke-iFlowAgent -Prompt $prompt -Mode "thinking"
    
    if ($result) {
        Write-Log "Generated implementation for: $($Feature.Name)" "SUCCESS"
        return $true
    }
    
    return $false
}

# =============================================================================
# Git Operations
# =============================================================================

function New-GitCommit {
    param([string]$Message)
    
    $quota = Get-QuotaPercentage
    if ($quota -lt 10) { return $false }
    
    $waitCount = 0
    while (Test-CommitLock -and $waitCount -lt 30) { Start-Sleep -Seconds 1; $waitCount++ }
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
        
        # Clean up temporary files before pull
        git checkout --ours commit.lock *.pid logs/ 2>$null
        git reset HEAD commit.lock *.pid logs/ 2>$null
        git checkout -- commit.lock *.pid logs/ 2>$null
        
        # Pull with rebase
        git pull --rebase origin $Branch 2>$null
        
        # Clean up any merge conflict markers in commit.lock
        if (Test-Path $COMMIT_LOCK) {
            $content = [System.IO.File]::ReadAllText($COMMIT_LOCK)
            if ($content -match "<<<<<<|======|>>>>>>") {
                [System.IO.File]::Delete($COMMIT_LOCK)
            }
        }
        
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
    Write-Log "Starting feature worker loop..."
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
        
        # Get next feature from queue
        $feature = Get-NextFeature
        
        if ($feature) {
            Update-Status "implementing"
            Write-Log "Processing feature: $($feature.Name)"
            
            $implemented = Implement-Feature -Feature $feature
            
            if ($implemented) {
                # Commit and push
                $committed = New-GitCommit -Message "Feature: $($feature.Name)"
                if ($committed) {
                    Write-Log "Pushing feature implementation..."
                    Sync-GitPush
                    
                    # Mark as completed
                    Save-CompletedFeature -Feature $feature
                    Remove-FeatureFromQueue
                    Write-Log "Feature completed: $($feature.Name)" "SUCCESS"
                }
            }
        } else {
            Write-Log "No features in queue. Waiting for new features..."
            Update-Status "waiting"
        }
        
        Start-Sleep -Seconds $IterationDelay
    }
    
    Update-Status "completed"
    Write-Log "Feature worker completed"
}

# =============================================================================
# Main
# =============================================================================

function Main {
    Write-Log "============================================"
    Write-Log "Feature Worker Starting"
    Write-Log "============================================"
    Write-Log "PID: $PID"
    Write-Log "Config: $Config"
    
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
    
    Write-Log "Feature Worker Exiting"
}

Main
