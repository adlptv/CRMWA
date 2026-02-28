#!/usr/bin/env pwsh
# AI Agent Loop Controller - PowerShell Version
# ==============================================
# Main controller for autonomous multi-agent AI development loop
# with quota monitoring and auto-recovery

param(
    [string]$RepoUrl = "",
    [string]$BranchName = "ai-dev",
    [switch]$SkipClone,
    [switch]$DryRun
)

# Set strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Project paths
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = $SCRIPT_DIR
$LOG_DIR = Join-Path $PROJECT_ROOT "logs"
$CONFIG_FILE = Join-Path $PROJECT_ROOT "config.env"

# State files
$SHUTDOWN_FLAG = Join-Path $PROJECT_ROOT "shutdown.flag"
$COMMIT_LOCK = Join-Path $PROJECT_ROOT "commit.lock"
$QUOTA_STATUS = Join-Path $PROJECT_ROOT "quota.status"
$RESTART_LOG = Join-Path $LOG_DIR "restart.log"
$CONTROLLER_PID = Join-Path $PROJECT_ROOT "controller.pid"

# Restart tracking
$RESTART_TRACKER = Join-Path $PROJECT_ROOT "restart.track"
$MAX_RESTART_ATTEMPTS = 3
$RESTART_WINDOW_MINUTES = 10

# Workers
$WORKERS = @("bugfix", "coverage", "refactor", "lint", "doc", "feature", "ideate")

# =============================================================================
# Logging Functions
# =============================================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARN" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor Cyan }
    }
    
    # Write to log file
    $logFile = Join-Path $LOG_DIR "controller.log"
    Add-Content -Path $logFile -Value $logMessage
}

function Write-RestartLog {
    param([string]$Message)
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Add-Content -Path $RESTART_LOG -Value $logMessage
}

# =============================================================================
# Configuration Functions
# =============================================================================

function Import-Config {
    if (Test-Path $CONFIG_FILE) {
        Get-Content $CONFIG_FILE | ForEach-Object {
            if ($_ -match '^([^#][^=]+)=(.*)$') {
                $name = $matches[1].Trim()
                $value = $matches[2].Trim().Trim('"').Trim("'")
                Set-Variable -Name $name -Value $value -Scope Script
            }
        }
        Write-Log "Configuration loaded from $CONFIG_FILE"
    } else {
        Write-Log "Using default configuration" "WARN"
    }
}

# =============================================================================
# Safety Functions
# =============================================================================

function Test-ShutdownFlag {
    return Test-Path $SHUTDOWN_FLAG
}

function Set-ShutdownFlag {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "SHUTDOWN_REQUESTED=$timestamp" | Out-File -FilePath $SHUTDOWN_FLAG
    Write-Log "Shutdown flag set" "WARN"
}

function Clear-ShutdownFlag {
    if (Test-Path $SHUTDOWN_FLAG) {
        Remove-Item $SHUTDOWN_FLAG -Force
        Write-Log "Shutdown flag cleared"
    }
}

function Test-CommitLock {
    return Test-Path $COMMIT_LOCK
}

function Set-CommitLock {
    $pid = $PID
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "PID=$pid`nTIMESTAMP=$timestamp" | Out-File -FilePath $COMMIT_LOCK
    Write-Log "Commit lock acquired by PID $pid"
}

function Clear-CommitLock {
    if (Test-Path $COMMIT_LOCK) {
        Remove-Item $COMMIT_LOCK -Force
        Write-Log "Commit lock released"
    }
}

function Wait-CommitLock {
    param([int]$TimeoutSeconds = 60)
    
    $startTime = Get-Date
    while (Test-CommitLock) {
        if (((Get-Date) - $startTime).TotalSeconds -gt $TimeoutSeconds) {
            Write-Log "Commit lock wait timeout exceeded" "ERROR"
            return $false
        }
        Write-Log "Waiting for commit lock..."
        Start-Sleep -Seconds 2
    }
    return $true
}

# =============================================================================
# Git Functions
# =============================================================================

function Initialize-GitRepository {
    param([string]$RepoUrl, [string]$BranchName)
    
    Write-Log "Initializing Git repository..."
    
    if ($RepoUrl) {
        # Clone repository
        Write-Log "Cloning repository: $RepoUrl"
        git clone $RepoUrl .
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to clone repository" "ERROR"
            return $false
        }
    } elseif (-not (Test-Path ".git")) {
        # Initialize new repository
        Write-Log "Initializing new Git repository"
        git init
        git config user.name "AI Agent"
        git config user.email "ai-agent@automaton.local"
    }
    
    # Create and switch to ai-dev branch
    $currentBranch = git branch --show-current 2>$null
    if ($currentBranch -ne $BranchName) {
        Write-Log "Creating/switching to branch: $BranchName"
        git checkout -b $BranchName 2>$null
        if ($LASTEXITCODE -ne 0) {
            git checkout $BranchName
        }
    }
    
    Write-Log "Git repository initialized on branch: $BranchName" "SUCCESS"
    return $true
}

function Reset-GitState {
    Write-Log "Resetting Git state..."
    git reset --hard HEAD
    git clean -fd
    Clear-CommitLock
    Write-Log "Git state reset complete"
}

# =============================================================================
# Restart Management
# =============================================================================

function Get-RestartCount {
    if (-not (Test-Path $RESTART_TRACKER)) {
        return 0
    }
    
    $content = Get-Content $RESTART_TRACKER
    $entries = $content | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}' }
    $cutoff = (Get-Date).AddMinutes(-$RESTART_WINDOW_MINUTES)
    
    $recentRestarts = $entries | ForEach-Object {
        if ($_ -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
            $date = [datetime]::ParseExact($matches[1], "yyyy-MM-dd HH:mm:ss", $null)
            if ($date -gt $cutoff) { $_ }
        }
    }
    
    return ($recentRestarts | Measure-Object).Count
}

function Register-Restart {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $RESTART_TRACKER -Value "$timestamp - Restart registered"
    Write-RestartLog "Restart registered at $timestamp"
}

function Test-CanRestart {
    $count = Get-RestartCount
    if ($count -ge $MAX_RESTART_ATTEMPTS) {
        Write-Log "Maximum restart attempts ($MAX_RESTART_ATTEMPTS) reached within $RESTART_WINDOW_MINUTES minutes" "ERROR"
        return $false
    }
    return $true
}

# =============================================================================
# Quota Functions
# =============================================================================

function Get-QuotaStatus {
    if (-not (Test-Path $QUOTA_STATUS)) {
        return @{ Percentage = 100; Available = "unknown"; Used = "unknown" }
    }
    
    $content = Get-Content $QUOTA_STATUS -Raw | ConvertFrom-Json
    return $content
}

function Test-QuotaCritical {
    $status = Get-QuotaStatus
    return ($status.Percentage -lt 10)
}

# =============================================================================
# Process Management
# =============================================================================

function Save-ControllerPid {
    $PID | Out-File -FilePath $CONTROLLER_PID
    Write-Log "Controller PID saved: $PID"
}

function Stop-WorkerProcesses {
    Write-Log "Stopping worker processes..."
    
    # Get all iflow processes
    $iflowProcesses = Get-Process -Name "node" -ErrorAction SilentlyContinue | 
        Where-Object { $_.CommandLine -like "*iflow*" }
    
    foreach ($proc in $iflowProcesses) {
        Write-Log "Stopping process: $($proc.Id)"
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    
    # Kill any remaining worker terminals
    Start-Sleep -Seconds 2
    
    Write-Log "Worker processes stopped"
}

function Start-QuotaMonitor {
    Write-Log "Starting quota monitor..."
    
    $monitorScript = Join-Path $PROJECT_ROOT "quota-monitor.ps1"
    if (Test-Path $monitorScript) {
        Start-Process -FilePath "powershell" -ArgumentList "-NoProfile", "-File", $monitorScript -WindowStyle Hidden
        Write-Log "Quota monitor started" "SUCCESS"
    } else {
        Write-Log "Quota monitor script not found: $monitorScript" "WARN"
    }
}

# =============================================================================
# Worker Spawning
# =============================================================================

function Start-Workers {
    Write-Log "Starting workers..."
    
    foreach ($worker in $WORKERS) {
        # Check for shutdown before each worker
        if (Test-ShutdownFlag) {
            Write-Log "Shutdown detected, aborting worker start" "WARN"
            return $false
        }
        
        $workerScript = Join-Path $PROJECT_ROOT "worker-$worker.ps1"
        if (Test-Path $workerScript) {
            Write-Log "Starting $worker worker..."
            
            if ($DryRun) {
                Write-Log "DRY RUN: Would start $worker worker"
            } else {
                Start-Process -FilePath "powershell" -ArgumentList "-NoProfile", "-File", $workerScript -WindowStyle Normal
                Start-Sleep -Seconds 2
            }
        } else {
            Write-Log "Worker script not found: $workerScript" "WARN"
        }
    }
    
    Write-Log "All workers started" "SUCCESS"
    return $true
}

# =============================================================================
# Main Controller Loop
# =============================================================================

function Invoke-ControllerLoop {
    Write-Log "Entering main controller loop..."
    
    $iteration = 0
    while ($true) {
        $iteration++
        Write-Log "=== Iteration $iteration ==="
        
        # Check for shutdown flag
        if (Test-ShutdownFlag) {
            Write-Log "Shutdown flag detected, initiating graceful shutdown..."
            
            # Check if we can restart
            if (Test-CanRestart) {
                Write-Log "Initiating restart sequence..."
                Register-Restart
                
                # Stop all workers
                Stop-WorkerProcesses
                
                # Reset git state
                Reset-GitState
                
                # Wait before restart
                Start-Sleep -Seconds 5
                
                # Clear shutdown flag
                Clear-ShutdownFlag
                
                # Restart workers
                Start-Workers
            } else {
                Write-Log "INSUFFICIENT QUOTA - SYSTEM HALTED" "ERROR"
                Write-RestartLog "SYSTEM HALTED - Max restart attempts exceeded"
                return
            }
        }
        
        # Check quota status
        $quota = Get-QuotaStatus
        Write-Log "Current quota: $($quota.Percentage)%"
        
        # Heartbeat
        $heartbeatFile = Join-Path $LOG_DIR "controller.heartbeat"
        Get-Date -Format "yyyy-MM-dd HH:mm:ss" | Out-File -FilePath $heartbeatFile
        
        # Sleep before next iteration
        Start-Sleep -Seconds 60
    }
}

# =============================================================================
# Main Entry Point
# =============================================================================

function Main {
    Write-Log "============================================"
    Write-Log "AI Agent Loop Controller Starting"
    Write-Log "============================================"
    Write-Log "Project Root: $PROJECT_ROOT"
    Write-Log "PID: $PID"
    
    # Create log directory if needed
    if (-not (Test-Path $LOG_DIR)) {
        New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
    }
    
    # Save controller PID
    Save-ControllerPid
    
    # Load configuration
    Import-Config
    
    # Initialize Git repository
    if (-not $SkipClone) {
        if (-not (Initialize-GitRepository -RepoUrl $RepoUrl -BranchName $BranchName)) {
            Write-Log "Failed to initialize Git repository" "ERROR"
            exit 1
        }
    }
    
    # Clear any stale flags
    Clear-ShutdownFlag
    Clear-CommitLock
    
    # Start quota monitor
    Start-QuotaMonitor
    
    # Start workers
    if (-not (Start-Workers)) {
        Write-Log "Failed to start workers" "ERROR"
        exit 1
    }
    
    # Enter main loop
    Invoke-ControllerLoop
}

# Run main function
Main
