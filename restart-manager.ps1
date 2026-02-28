#!/usr/bin/env pwsh
# Restart Manager Script - PowerShell Version
# ============================================
# Handles controlled restart of the AI agent loop system

param(
    [int]$RestartDelay = 5,
    [int]$MaxRestarts = 3,
    [int]$RestartWindowMinutes = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = $SCRIPT_DIR
$LOG_DIR = Join-Path $PROJECT_ROOT "logs"
$SHUTDOWN_FLAG = Join-Path $PROJECT_ROOT "shutdown.flag"
$COMMIT_LOCK = Join-Path $PROJECT_ROOT "commit.lock"
$RESTART_LOG = Join-Path $LOG_DIR "restart.log"
$RESTART_TRACKER = Join-Path $PROJECT_ROOT "restart.track"

$WORKERS = @("bugfix", "coverage", "refactor", "lint", "doc")

# =============================================================================
# Logging
# =============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [RESTART-MANAGER] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARN" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor Cyan }
    }
    
    Add-Content -Path $RESTART_LOG -Value $logMessage
}

# =============================================================================
# Restart Tracking
# =============================================================================

function Get-RestartCount {
    if (-not (Test-Path $RESTART_TRACKER)) {
        return 0
    }
    
    $content = Get-Content $RESTART_TRACKER
    $cutoff = (Get-Date).AddMinutes(-$RestartWindowMinutes)
    
    $recentRestarts = $content | Where-Object {
        if ($_ -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
            try {
                $date = [datetime]::ParseExact($matches[1], "yyyy-MM-dd HH:mm:ss", $null)
                return $date -gt $cutoff
            } catch {
                return $false
            }
        }
        return $false
    }
    
    return ($recentRestarts | Measure-Object).Count
}

function Register-Restart {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - Restart initiated" | Add-Content -Path $RESTART_TRACKER
    Write-Log "Restart registered at $timestamp"
}

function Test-CanRestart {
    $count = Get-RestartCount
    if ($count -ge $MaxRestarts) {
        Write-Log "Maximum restart attempts ($MaxRestarts) reached within $RestartWindowMinutes minutes" "ERROR"
        return $false
    }
    return $true
}

# =============================================================================
# Process Management
# =============================================================================

function Stop-AllWorkers {
    Write-Log "Stopping all worker processes..."
    
    foreach ($worker in $WORKERS) {
        $pidFile = Join-Path $PROJECT_ROOT "worker-$worker.pid"
        
        if (Test-Path $pidFile) {
            $pid = Get-Content $pidFile -ErrorAction SilentlyContinue
            if ($pid) {
                try {
                    $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
                    if ($process) {
                        Write-Log "Stopping $worker worker (PID: $pid)"
                        Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
                    }
                } catch {
                    Write-Log "Failed to stop $worker worker: $_" "WARN"
                }
            }
            Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Kill any remaining iflow processes
    $iflowProcesses = Get-Process -Name "node" -ErrorAction SilentlyContinue | 
        Where-Object { $_.CommandLine -like "*iflow*" -or $_.MainWindowTitle -like "*iflow*" }
    
    foreach ($proc in $iflowProcesses) {
        Write-Log "Stopping orphaned iflow process (PID: $($proc.Id))"
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    
    Start-Sleep -Seconds 2
    Write-Log "All workers stopped" "SUCCESS"
}

function Stop-Controller {
    Write-Log "Stopping controller..."
    
    $controllerPidFile = Join-Path $PROJECT_ROOT "controller.pid"
    
    if (Test-Path $controllerPidFile) {
        $pid = Get-Content $controllerPidFile -ErrorAction SilentlyContinue
        if ($pid) {
            try {
                $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
                if ($process) {
                    Write-Log "Stopping controller (PID: $pid)"
                    Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
                }
            } catch {
                Write-Log "Failed to stop controller: $_" "WARN"
            }
        }
        Remove-Item $controllerPidFile -Force -ErrorAction SilentlyContinue
    }
}

function Stop-QuotaMonitor {
    Write-Log "Stopping quota monitor..."
    
    # Find and stop quota monitor processes
    $monitorProcesses = Get-Process -Name "pwsh", "powershell" -ErrorAction SilentlyContinue | 
        Where-Object { $_.CommandLine -like "*quota-monitor*" }
    
    foreach ($proc in $monitorProcesses) {
        Write-Log "Stopping quota monitor (PID: $($proc.Id))"
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# State Cleanup
# =============================================================================

function Clear-AllLocks {
    Write-Log "Clearing all locks..."
    
    if (Test-Path $COMMIT_LOCK) {
        Remove-Item $COMMIT_LOCK -Force -ErrorAction SilentlyContinue
        Write-Log "Commit lock cleared"
    }
    
    if (Test-Path $SHUTDOWN_FLAG) {
        Remove-Item $SHUTDOWN_FLAG -Force -ErrorAction SilentlyContinue
        Write-Log "Shutdown flag cleared"
    }
}

function Reset-GitState {
    Write-Log "Resetting Git state..."
    
    Push-Location $PROJECT_ROOT
    try {
        git reset --hard HEAD 2>$null
        git clean -fd 2>$null
        Write-Log "Git state reset" "SUCCESS"
    } catch {
        Write-Log "Git reset failed: $_" "WARN"
    }
    Pop-Location
}

# =============================================================================
# Restart Execution
# =============================================================================

function Start-Controller {
    Write-Log "Starting controller..."
    
    $controllerScript = Join-Path $PROJECT_ROOT "controller.ps1"
    
    if (Test-Path $controllerScript) {
        Start-Process -FilePath "pwsh" -ArgumentList "-File", $controllerScript, "-SkipClone" -WindowStyle Normal
        Write-Log "Controller started" "SUCCESS"
    } else {
        Write-Log "Controller script not found: $controllerScript" "ERROR"
    }
}

function Invoke-Restart {
    Write-Log "============================================"
    Write-Log "Initiating System Restart"
    Write-Log "============================================"
    
    # Check if we can restart
    if (-not (Test-CanRestart)) {
        Write-Log "INSUFFICIENT QUOTA - SYSTEM HALTED" "ERROR"
        Write-Log "Maximum restart attempts exceeded. Manual intervention required."
        
        # Create halt marker
        $haltFile = Join-Path $LOG_DIR "system.halted"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "HALTED at $timestamp - Max restarts exceeded" | Out-File $haltFile
        
        return $false
    }
    
    # Register restart
    Register-Restart
    
    # Phase 1: Stop all processes
    Write-Log "Phase 1: Stopping processes..."
    Stop-AllWorkers
    Stop-Controller
    Stop-QuotaMonitor
    
    # Phase 2: Cleanup state
    Write-Log "Phase 2: Cleaning up state..."
    Clear-AllLocks
    Reset-GitState
    
    # Phase 3: Wait
    Write-Log "Phase 3: Waiting $RestartDelay seconds..."
    Start-Sleep -Seconds $RestartDelay
    
    # Phase 4: Restart
    Write-Log "Phase 4: Starting system..."
    Start-Controller
    
    Write-Log "Restart completed successfully" "SUCCESS"
    return $true
}

# =============================================================================
# Main
# =============================================================================

function Main {
    Write-Log "============================================"
    Write-Log "Restart Manager Starting"
    Write-Log "============================================"
    Write-Log "PID: $PID"
    Write-Log "Max Restarts: $MaxRestarts"
    Write-Log "Restart Window: $RestartWindowMinutes minutes"
    
    # Ensure log directory exists
    if (-not (Test-Path $LOG_DIR)) {
        New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
    }
    
    # Execute restart
    $success = Invoke-Restart
    
    if (-not $success) {
        exit 1
    }
    
    exit 0
}

Main
