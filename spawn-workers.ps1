#!/usr/bin/env pwsh
# Spawn Workers Script - PowerShell Version
# ==========================================
# Spawns all worker agents in separate terminal windows

param(
    [int]$WorkerDelay = 2,
    [switch]$Background,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = $SCRIPT_DIR
$LOG_DIR = Join-Path $PROJECT_ROOT "logs"
$CONFIG_FILE = Join-Path $PROJECT_ROOT "config.env"
$SHUTDOWN_FLAG = Join-Path $PROJECT_ROOT "shutdown.flag"
$COMMIT_LOCK = Join-Path $PROJECT_ROOT "commit.lock"

$WORKERS = @(
    @{ Name = "bugfix"; Config = "iflow-bugfix.yaml"; Priority = 1 }
    @{ Name = "coverage"; Config = "iflow-coverage.yaml"; Priority = 2 }
    @{ Name = "refactor"; Config = "iflow-refactor.yaml"; Priority = 3 }
    @{ Name = "lint"; Config = "iflow-lint.yaml"; Priority = 4 }
    @{ Name = "doc"; Config = "iflow-doc.yaml"; Priority = 5 }
)

# =============================================================================
# Logging
# =============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARN" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor Cyan }
    }
    
    $logFile = Join-Path $LOG_DIR "spawn-workers.log"
    Add-Content -Path $logFile -Value $logMessage
}

# =============================================================================
# Safety Checks
# =============================================================================

function Test-ShutdownFlag {
    return Test-Path $SHUTDOWN_FLAG
}

function Test-CommitLock {
    return Test-Path $COMMIT_LOCK
}

function Wait-CommitLock {
    param([int]$TimeoutSeconds = 60)
    
    $startTime = Get-Date
    while (Test-CommitLock) {
        if (((Get-Date) - $startTime).TotalSeconds -gt $TimeoutSeconds) {
            return $false
        }
        Write-Log "Waiting for commit lock to be released..."
        Start-Sleep -Seconds 2
    }
    return $true
}

# =============================================================================
# Worker Functions
# =============================================================================

function Start-Worker {
    param(
        [string]$Name,
        [string]$Config,
        [int]$Priority
    )
    
    # Check for shutdown before starting
    if (Test-ShutdownFlag) {
        Write-Log "Shutdown flag detected, not starting worker: $Name" "WARN"
        return $false
    }
    
    $workerScript = Join-Path $PROJECT_ROOT "worker-$Name.ps1"
    
    if (-not (Test-Path $workerScript)) {
        Write-Log "Worker script not found: $workerScript" "ERROR"
        return $false
    }
    
    $configPath = Join-Path $PROJECT_ROOT $Config
    if (-not (Test-Path $configPath)) {
        Write-Log "Worker config not found: $configPath" "WARN"
    }
    
    Write-Log "Starting worker: $Name (Priority: $Priority)"
    
    if ($DryRun) {
        Write-Log "DRY RUN: Would start $Name worker"
        return $true
    }
    
    try {
        if ($Background) {
            # Run in background without window
            Start-Process -FilePath "pwsh" `
                -ArgumentList "-NoProfile", "-File", $workerScript `
                -WindowStyle Hidden `
                -RedirectStandardOutput (Join-Path $LOG_DIR "worker-$Name-stdout.log") `
                -RedirectStandardError (Join-Path $LOG_DIR "worker-$Name-stderr.log")
        } else {
            # Run in new terminal window
            Start-Process -FilePath "pwsh" `
                -ArgumentList "-NoProfile", "-File", $workerScript `
                -WindowStyle Normal
        }
        
        Write-Log "Worker $Name started successfully" "SUCCESS"
        return $true
    } catch {
        Write-Log "Failed to start worker $Name : $_" "ERROR"
        return $false
    }
}

function Start-AllWorkers {
    Write-Log "Starting all workers..."
    
    # Sort by priority
    $sortedWorkers = $WORKERS | Sort-Object { $_.Priority }
    
    $startedCount = 0
    $failedCount = 0
    
    foreach ($worker in $sortedWorkers) {
        # Check for shutdown flag between workers
        if (Test-ShutdownFlag) {
            Write-Log "Shutdown flag detected, stopping worker spawn" "WARN"
            break
        }
        
        # Wait for commit lock if present
        if (-not (Wait-CommitLock -TimeoutSeconds 30)) {
            Write-Log "Could not acquire lock for worker spawn, skipping..." "WARN"
        }
        
        $success = Start-Worker -Name $worker.Name -Config $worker.Config -Priority $worker.Priority
        
        if ($success) {
            $startedCount++
        } else {
            $failedCount++
        }
        
        # Delay between worker starts
        if ($WorkerDelay -gt 0) {
            Start-Sleep -Seconds $WorkerDelay
        }
    }
    
    Write-Log "Worker spawn complete. Started: $startedCount, Failed: $failedCount"
    
    return @{
        Started = $startedCount
        Failed = $failedCount
        Total = $WORKERS.Count
    }
}

# =============================================================================
# Status Functions
# =============================================================================

function Get-WorkerStatus {
    $status = @{}
    
    foreach ($worker in $WORKERS) {
        $name = $worker.Name
        $statusFile = Join-Path $LOG_DIR "worker-$name-status.txt"
        $pidFile = Join-Path $PROJECT_ROOT "worker-$name.pid"
        
        $workerStatus = @{
            Name = $name
            Config = $worker.Config
            Priority = $worker.Priority
            Running = $false
            PID = $null
            Status = "unknown"
            LastUpdate = $null
        }
        
        # Check PID file
        if (Test-Path $pidFile) {
            $pid = Get-Content $pidFile -ErrorAction SilentlyContinue
            if ($pid) {
                $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
                if ($process) {
                    $workerStatus.Running = $true
                    $workerStatus.PID = $pid
                }
            }
        }
        
        # Check status file
        if (Test-Path $statusFile) {
            $statusContent = Get-Content $statusFile -ErrorAction SilentlyContinue
            if ($statusContent) {
                $workerStatus.Status = $statusContent.Trim()
                $workerStatus.LastUpdate = (Get-Item $statusFile).LastWriteTime
            }
        }
        
        $status[$name] = $workerStatus
    }
    
    return $status
}

function Show-WorkerStatus {
    $status = Get-WorkerStatus
    
    Write-Host ""
    Write-Host "Worker Status Summary" -ForegroundColor Cyan
    Write-Host "=====================" -ForegroundColor Cyan
    Write-Host ""
    
    $status.Values | ForEach-Object {
        $runningColor = if ($_.Running) { "Green" } else { "Red" }
        $runningText = if ($_.Running) { "RUNNING" } else { "STOPPED" }
        
        Write-Host "  $($_.Name): " -NoNewline
        Write-Host $runningText -ForegroundColor $runningColor -NoNewline
        Write-Host " (PID: $($_.PID), Status: $($_.Status))"
    }
    
    Write-Host ""
}

# =============================================================================
# Main
# =============================================================================

function Main {
    Write-Log "============================================"
    Write-Log "Worker Spawn Script Starting"
    Write-Log "============================================"
    
    # Ensure log directory exists
    if (-not (Test-Path $LOG_DIR)) {
        New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
    }
    
    # Check for existing shutdown flag
    if (Test-ShutdownFlag) {
        Write-Log "Shutdown flag is set. Clearing before spawn..." "WARN"
        Remove-Item $SHUTDOWN_FLAG -Force
    }
    
    # Start all workers
    $result = Start-AllWorkers
    
    # Show status
    Show-WorkerStatus
    
    Write-Log "Spawn complete: $($result.Started)/$($result.Total) workers started"
    
    if ($result.Failed -gt 0) {
        Write-Log "Some workers failed to start. Check logs for details." "WARN"
        exit 1
    }
    
    exit 0
}

Main
