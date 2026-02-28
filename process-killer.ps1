#!/usr/bin/env pwsh
# Process Killer Script - PowerShell Version
# ===========================================
# Utility for forcefully terminating AI agent loop processes

param(
    [switch]$All,
    [switch]$Workers,
    [switch]$Controller,
    [switch]$QuotaMonitor,
    [string]$Worker,
    [int]$Timeout = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = $SCRIPT_DIR
$LOG_DIR = Join-Path $PROJECT_ROOT "logs"

$WORKERS = @("bugfix", "coverage", "refactor", "lint", "doc")

# =============================================================================
# Logging
# =============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [PROCESS-KILLER] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARN" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor Cyan }
    }
}

# =============================================================================
# Process Functions
# =============================================================================

function Stop-ProcessByPidFile {
    param([string]$PidFile, [string]$ProcessName)
    
    if (-not (Test-Path $PidFile)) {
        Write-Log "PID file not found: $PidFile" "WARN"
        return $false
    }
    
    $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if (-not $pid) {
        Write-Log "No PID in file: $PidFile" "WARN"
        return $false
    }
    
    try {
        $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if (-not $process) {
            Write-Log "$ProcessName process not running (PID: $pid)" "WARN"
            return $true
        }
        
        Write-Log "Stopping $ProcessName (PID: $pid)..."
        
        # Try graceful termination first
        Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
        
        # Wait for process to exit
        $waited = 0
        while ((Get-Process -Id $pid -ErrorAction SilentlyContinue) -and ($waited -lt $Timeout)) {
            Start-Sleep -Milliseconds 100
            $waited += 100
        }
        
        # Force kill if still running
        if (Get-Process -Id $pid -ErrorAction SilentlyContinue) {
            Write-Log "Force killing $ProcessName (PID: $pid)" "WARN"
            Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
        }
        
        # Remove PID file
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
        
        Write-Log "$ProcessName stopped" "SUCCESS"
        return $true
    } catch {
        Write-Log "Failed to stop $ProcessName : $_" "ERROR"
        return $false
    }
}

function Stop-Worker {
    param([string]$WorkerName)
    
    $pidFile = Join-Path $PROJECT_ROOT "worker-$WorkerName.pid"
    Stop-ProcessByPidFile -PidFile $pidFile -ProcessName "$WorkerName worker"
}

function Stop-AllWorkers {
    Write-Log "Stopping all workers..."
    
    foreach ($worker in $WORKERS) {
        Stop-Worker -WorkerName $worker
    }
}

function Stop-Controller {
    $pidFile = Join-Path $PROJECT_ROOT "controller.pid"
    Stop-ProcessByPidFile -PidFile $pidFile -ProcessName "controller"
}

function Stop-QuotaMonitor {
    Write-Log "Stopping quota monitor..."
    
    # Find quota monitor processes
    $monitorProcesses = Get-Process -Name "pwsh", "powershell" -ErrorAction SilentlyContinue | 
        Where-Object { $_.CommandLine -like "*quota-monitor*" }
    
    foreach ($proc in $monitorProcesses) {
        Write-Log "Stopping quota monitor (PID: $($proc.Id))"
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    
    Write-Log "Quota monitor stopped" "SUCCESS"
}

function Stop-AllIFlowProcesses {
    Write-Log "Stopping all iFlow processes..."
    
    # Get all node processes that might be iFlow
    $nodeProcesses = Get-Process -Name "node" -ErrorAction SilentlyContinue
    
    foreach ($proc in $nodeProcesses) {
        # Check if it's an iflow process
        $isIflow = $false
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
            if ($cmdLine -like "*iflow*") {
                $isIflow = $true
            }
        } catch {
            # If we can't check, assume it's not iflow
        }
        
        if ($isIflow) {
            Write-Log "Stopping iFlow process (PID: $($proc.Id))"
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-Log "All iFlow processes stopped" "SUCCESS"
}

function Stop-Everything {
    Write-Log "============================================"
    Write-Log "Stopping All Processes"
    Write-Log "============================================"
    
    Stop-AllWorkers
    Stop-Controller
    Stop-QuotaMonitor
    Stop-AllIFlowProcesses
    
    Write-Log "All processes stopped" "SUCCESS"
}

function Show-ProcessStatus {
    Write-Host ""
    Write-Host "Process Status" -ForegroundColor Cyan
    Write-Host "==============" -ForegroundColor Cyan
    Write-Host ""
    
    # Check controller
    $controllerPidFile = Join-Path $PROJECT_ROOT "controller.pid"
    if (Test-Path $controllerPidFile) {
        $pid = Get-Content $controllerPidFile -ErrorAction SilentlyContinue
        if ($pid) {
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($proc) {
                Write-Host "  Controller: " -NoNewline
                Write-Host "RUNNING" -ForegroundColor Green -NoNewline
                Write-Host " (PID: $pid)"
            } else {
                Write-Host "  Controller: " -NoNewline
                Write-Host "STOPPED (stale PID file)" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "  Controller: " -NoNewline
        Write-Host "NOT STARTED" -ForegroundColor Yellow
    }
    
    # Check workers
    foreach ($worker in $WORKERS) {
        $pidFile = Join-Path $PROJECT_ROOT "worker-$worker.pid"
        if (Test-Path $pidFile) {
            $pid = Get-Content $pidFile -ErrorAction SilentlyContinue
            if ($pid) {
                $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
                if ($proc) {
                    Write-Host "  $worker worker: " -NoNewline
                    Write-Host "RUNNING" -ForegroundColor Green -NoNewline
                    Write-Host " (PID: $pid)"
                } else {
                    Write-Host "  $worker worker: " -NoNewline
                    Write-Host "STOPPED (stale PID file)" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "  $worker worker: " -NoNewline
            Write-Host "NOT STARTED" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
}

# =============================================================================
# Main
# =============================================================================

function Main {
    Write-Log "Process Killer - PID: $PID"
    
    # Ensure log directory exists
    if (-not (Test-Path $LOG_DIR)) {
        New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
    }
    
    if ($All) {
        Stop-Everything
    } elseif ($Workers) {
        Stop-AllWorkers
    } elseif ($Controller) {
        Stop-Controller
    } elseif ($QuotaMonitor) {
        Stop-QuotaMonitor
    } elseif ($Worker) {
        Stop-Worker -WorkerName $Worker
    } else {
        Show-ProcessStatus
    }
}

Main
