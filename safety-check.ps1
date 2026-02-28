#!/usr/bin/env pwsh
# Safety Check Script - PowerShell Version
# =========================================
# Performs safety checks before critical operations

param(
    [switch]$All,
    [switch]$Git,
    [switch]$Locks,
    [switch]$Processes,
    [switch]$Quota,
    [switch]$Disk,
    [switch]$Memory,
    [switch]$Network,
    [switch]$Fix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = $SCRIPT_DIR
$LOG_DIR = Join-Path $PROJECT_ROOT "logs"
$SHUTDOWN_FLAG = Join-Path $PROJECT_ROOT "shutdown.flag"
$COMMIT_LOCK = Join-Path $PROJECT_ROOT "commit.lock"
$QUOTA_STATUS = Join-Path $PROJECT_ROOT "quota.status"

$issues = @()
$warnings = @()

# =============================================================================
# Output Functions
# =============================================================================

function Add-Issue {
    param([string]$Message)
    $script:issues += $Message
    Write-Host "  [ISSUE] $Message" -ForegroundColor Red
}

function Add-Warning {
    param([string]$Message)
    $script:warnings += $Message
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Add-Ok {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

# =============================================================================
# Git Safety Checks
# =============================================================================

function Test-GitSafety {
    Write-Host ""
    Write-Host "Git Safety Checks" -ForegroundColor Cyan
    Write-Host "================="
    
    Push-Location $PROJECT_ROOT
    try {
        # Check if in git repository
        $inGitRepo = $false
        try {
            $null = git rev-parse --git-dir 2>$null
            $inGitRepo = $true
        } catch {}
        
        if (-not $inGitRepo) {
            Add-Warning "Not in a Git repository"
        } else {
            Add-Ok "In Git repository"
            
            # Check for uncommitted changes
            $status = git status --porcelain 2>$null
            if ($status) {
                Add-Warning "Uncommitted changes detected"
            } else {
                Add-Ok "Working directory clean"
            }
            
            # Check current branch
            $branch = git branch --show-current 2>$null
            Add-Ok "Current branch: $branch"
            
            # Check for detached HEAD
            $isDetached = git symbolic-ref -q HEAD 2>$null
            if (-not $isDetached) {
                Add-Warning "Detached HEAD state"
            }
            
            # Check for merge conflicts
            $conflicts = git diff --name-only --diff-filter=U 2>$null
            if ($conflicts) {
                Add-Issue "Merge conflicts detected"
            }
        }
    } finally {
        Pop-Location
    }
}

# =============================================================================
# Lock Safety Checks
# =============================================================================

function Test-LockSafety {
    Write-Host ""
    Write-Host "Lock Safety Checks" -ForegroundColor Cyan
    Write-Host "=================="
    
    # Check shutdown flag
    if (Test-Path $SHUTDOWN_FLAG) {
        $flagContent = Get-Content $SHUTDOWN_FLAG
        Add-Issue "Shutdown flag is set"
        Write-Host "    Content: $flagContent" -ForegroundColor Gray
        
        if ($Fix) {
            Remove-Item $SHUTDOWN_FLAG -Force
            Write-Host "    [FIXED] Removed shutdown flag" -ForegroundColor Green
        }
    } else {
        Add-Ok "No shutdown flag"
    }
    
    # Check commit lock
    if (Test-Path $COMMIT_LOCK) {
        $lockContent = Get-Content $COMMIT_LOCK
        Add-Warning "Commit lock is set"
        Write-Host "    Content: $lockContent" -ForegroundColor Gray
        
        # Check if lock is stale (older than 5 minutes)
        if ($lockContent -match "TIMESTAMP=(.+)") {
            try {
                $lockTime = [datetime]::ParseExact($matches[1].Trim(), "yyyy-MM-dd HH:mm:ss", $null)
                $age = (Get-Date) - $lockTime
                if ($age.TotalMinutes -gt 5) {
                    Add-Warning "Commit lock is stale (${age.TotalMinutes:N1} minutes old)"
                    
                    if ($Fix) {
                        Remove-Item $COMMIT_LOCK -Force
                        Write-Host "    [FIXED] Removed stale commit lock" -ForegroundColor Green
                    }
                }
            } catch {}
        }
    } else {
        Add-Ok "No commit lock"
    }
}

# =============================================================================
# Process Safety Checks
# =============================================================================

function Test-ProcessSafety {
    Write-Host ""
    Write-Host "Process Safety Checks" -ForegroundColor Cyan
    Write-Host "====================="
    
    $workers = @("bugfix", "coverage", "refactor", "lint", "doc")
    
    # Check controller
    $controllerPidFile = Join-Path $PROJECT_ROOT "controller.pid"
    if (Test-Path $controllerPidFile) {
        $pid = Get-Content $controllerPidFile -ErrorAction SilentlyContinue
        if ($pid) {
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($proc) {
                Add-Ok "Controller running (PID: $pid)"
            } else {
                Add-Warning "Controller PID file exists but process not running (stale PID: $pid)"
            }
        }
    } else {
        Add-Ok "Controller not running"
    }
    
    # Check workers
    $runningWorkers = 0
    foreach ($worker in $workers) {
        $pidFile = Join-Path $PROJECT_ROOT "worker-$worker.pid"
        if (Test-Path $pidFile) {
            $pid = Get-Content $pidFile -ErrorAction SilentlyContinue
            if ($pid) {
                $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
                if ($proc) {
                    $runningWorkers++
                    Add-Ok "$worker worker running (PID: $pid)"
                } else {
                    Add-Warning "$worker worker PID file exists but process not running"
                    
                    if ($Fix) {
                        Remove-Item $pidFile -Force
                        Write-Host "    [FIXED] Removed stale PID file" -ForegroundColor Green
                    }
                }
            }
        }
    }
    
    if ($runningWorkers -eq 0) {
        Add-Warning "No workers running"
    }
}

# =============================================================================
# Quota Safety Checks
# =============================================================================

function Test-QuotaSafety {
    Write-Host ""
    Write-Host "Quota Safety Checks" -ForegroundColor Cyan
    Write-Host "==================="
    
    if (Test-Path $QUOTA_STATUS) {
        try {
            $content = Get-Content $QUOTA_STATUS -Raw | ConvertFrom-Json
            $percentage = $content.Percentage
            $status = $content.Status
            $timestamp = $content.Timestamp
            
            Add-Ok "Quota status available"
            Write-Host "    Percentage: $percentage%" -ForegroundColor Gray
            Write-Host "    Status: $status" -ForegroundColor Gray
            Write-Host "    Last check: $timestamp" -ForegroundColor Gray
            
            if ($percentage -le 10) {
                Add-Issue "Quota is critical ($percentage%)"
            } elseif ($percentage -le 25) {
                Add-Warning "Quota is low ($percentage%)"
            } else {
                Add-Ok "Quota is healthy"
            }
        } catch {
            Add-Warning "Could not parse quota status file"
        }
    } else {
        Add-Warning "No quota status file"
    }
}

# =============================================================================
# Disk Safety Checks
# =============================================================================

function Test-DiskSafety {
    Write-Host ""
    Write-Host "Disk Safety Checks" -ForegroundColor Cyan
    Write-Host "=================="
    
    $drive = (Get-Item $PROJECT_ROOT).PSDrive
    
    if ($drive) {
        $used = $drive.Used
        $free = $drive.Free
        $total = $used + $free
        $freePercent = [math]::Round(($free / $total) * 100, 1)
        $freeGB = [math]::Round($free / 1GB, 2)
        
        Add-Ok "Drive $($drive.Name): $freeGB GB free ($freePercent%)"
        
        if ($freePercent -lt 5) {
            Add-Issue "Disk space critical ($freePercent% free)"
        } elseif ($freePercent -lt 10) {
            Add-Warning "Disk space low ($freePercent% free)"
        }
        
        # Check log directory size
        if (Test-Path $LOG_DIR) {
            $logSize = (Get-ChildItem $LOG_DIR -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $logSizeMB = [math]::Round($logSize / 1MB, 2)
            Add-Ok "Log directory size: $logSizeMB MB"
            
            if ($logSizeMB -gt 100) {
                Add-Warning "Log directory is large"
            }
        }
    }
}

# =============================================================================
# Memory Safety Checks
# =============================================================================

function Test-MemorySafety {
    Write-Host ""
    Write-Host "Memory Safety Checks" -ForegroundColor Cyan
    Write-Host "===================="
    
    $os = Get-CimInstance Win32_OperatingSystem
    $totalMemory = $os.TotalVisibleMemorySize * 1KB
    $freeMemory = $os.FreePhysicalMemory * 1KB
    $usedMemory = $totalMemory - $freeMemory
    $freePercent = [math]::Round(($freeMemory / $totalMemory) * 100, 1)
    $freeGB = [math]::Round($freeMemory / 1GB, 2)
    
    Add-Ok "Free memory: $freeGB GB ($freePercent%)"
    
    if ($freePercent -lt 5) {
        Add-Issue "Memory critical ($freePercent% free)"
    } elseif ($freePercent -lt 15) {
        Add-Warning "Memory low ($freePercent% free)"
    }
    
    # Check for high memory processes
    $highMemoryProcesses = Get-Process | Where-Object { $_.WorkingSet64 -gt 500MB } | 
        Sort-Object WorkingSet64 -Descending | Select-Object -First 5
    
    if ($highMemoryProcesses) {
        Add-Warning "High memory processes detected"
        foreach ($proc in $highMemoryProcesses) {
            $memMB = [math]::Round($proc.WorkingSet64 / 1MB, 0)
            Write-Host "    $($proc.ProcessName): $memMB MB" -ForegroundColor Gray
        }
    }
}

# =============================================================================
# Network Safety Checks
# =============================================================================

function Test-NetworkSafety {
    Write-Host ""
    Write-Host "Network Safety Checks" -ForegroundColor Cyan
    Write-Host "====================="
    
    # Check if iFlow CLI is accessible
    try {
        $iflowVersion = & iflow --version 2>&1
        Add-Ok "iFlow CLI accessible"
    } catch {
        Add-Warning "iFlow CLI not found in PATH"
    }
    
    # Check Git connectivity (if in repo)
    Push-Location $PROJECT_ROOT
    try {
        $remote = git remote get-url origin 2>$null
        if ($remote) {
            Add-Ok "Git remote configured: $remote"
        }
    } catch {}
    Pop-Location
}

# =============================================================================
# Summary
# =============================================================================

function Show-Summary {
    Write-Host ""
    Write-Host "============================================"
    Write-Host "Safety Check Summary" -ForegroundColor Cyan
    Write-Host "============================================"
    Write-Host ""
    
    $totalIssues = $issues.Count
    $totalWarnings = $warnings.Count
    
    Write-Host "Issues:    $totalIssues" -ForegroundColor $(if ($totalIssues -gt 0) { "Red" } else { "Green" })
    Write-Host "Warnings:  $totalWarnings" -ForegroundColor $(if ($totalWarnings -gt 0) { "Yellow" } else { "Green" })
    
    if ($totalIssues -gt 0) {
        Write-Host ""
        Write-Host "Issues found:" -ForegroundColor Red
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
    }
    
    Write-Host ""
    
    if ($totalIssues -gt 0) {
        Write-Host "SAFETY CHECK FAILED" -ForegroundColor Red
        return 1
    } elseif ($totalWarnings -gt 0) {
        Write-Host "SAFETY CHECK PASSED (with warnings)" -ForegroundColor Yellow
        return 0
    } else {
        Write-Host "SAFETY CHECK PASSED" -ForegroundColor Green
        return 0
    }
}

# =============================================================================
# Main
# =============================================================================

function Main {
    Write-Host "============================================"
    Write-Host "AI Agent Loop Safety Checker" -ForegroundColor Cyan
    Write-Host "============================================"
    Write-Host "Project: $PROJECT_ROOT"
    Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    if ($All -or (-not ($Git -or $Locks -or $Processes -or $Quota -or $Disk -or $Memory -or $Network))) {
        $Git = $true
        $Locks = $true
        $Processes = $true
        $Quota = $true
        $Disk = $true
        $Memory = $true
        $Network = $true
    }
    
    if ($Git) { Test-GitSafety }
    if ($Locks) { Test-LockSafety }
    if ($Processes) { Test-ProcessSafety }
    if ($Quota) { Test-QuotaSafety }
    if ($Disk) { Test-DiskSafety }
    if ($Memory) { Test-MemorySafety }
    if ($Network) { Test-NetworkSafety }
    
    $exitCode = Show-Summary
    exit $exitCode
}

Main
