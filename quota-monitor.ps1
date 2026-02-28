#!/usr/bin/env pwsh
# Quota Monitor Script - PowerShell Version
# ==========================================
# Background process that monitors GLM-5 agent quota
# and triggers controlled shutdown when quota is critical

param(
    [int]$CheckInterval = 60,
    [int]$CriticalThreshold = 10,
    [int]$WarningThreshold = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = $SCRIPT_DIR
$LOG_DIR = Join-Path $PROJECT_ROOT "logs"
$QUOTA_STATUS = Join-Path $PROJECT_ROOT "quota.status"
$SHUTDOWN_FLAG = Join-Path $PROJECT_ROOT "shutdown.flag"
$QUOTA_LOG = Join-Path $LOG_DIR "quota-monitor.log"

# =============================================================================
# Logging
# =============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [QUOTA-MONITOR] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARN" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor Cyan }
    }
    
    Add-Content -Path $QUOTA_LOG -Value $logMessage
}

# =============================================================================
# Quota Detection Methods
# =============================================================================

function Get-QuotaFromiFlowStatus {
    <#
    .SYNOPSIS
    Attempts to get quota information from iFlow CLI status command
    #>
    
    try {
        # Try iFlow status command
        $statusOutput = & iflow status 2>&1
        
        # Parse output for quota information
        if ($statusOutput -match "quota[:\s]+(\d+)%") {
            return [int]$matches[1]
        }
        if ($statusOutput -match "remaining[:\s]+(\d+)%") {
            return [int]$matches[1]
        }
        if ($statusOutput -match "usage[:\s]+(\d+)%") {
            return 100 - [int]$matches[1]
        }
        
        return $null
    } catch {
        return $null
    }
}

function Get-QuotaFromEnvironment {
    <#
    .SYNOPSIS
    Attempts to get quota from environment variables
    #>
    
    $envQuota = $env:IFLOW_QUOTA_PERCENTAGE
    if ($envQuota) {
        try {
            return [int]$envQuota
        } catch {
            return $null
        }
    }
    
    return $null
}

function Get-QuotaFromMetricsFile {
    <#
    .SYNOPSIS
    Attempts to get quota from iFlow metrics file
    #>
    
    $possiblePaths = @(
        "$env:USERPROFILE\.iflow\metrics.json",
        "$env:HOME\.iflow\metrics.json",
        "$env:APPDATA\iflow\metrics.json",
        "$PROJECT_ROOT\.iflow\metrics.json"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            try {
                $content = Get-Content $path -Raw | ConvertFrom-Json
                
                if ($content.quota) {
                    return [int]$content.quota
                }
                if ($content.remaining_quota) {
                    return [int]$content.remaining_quota
                }
                if ($content.quota_percentage) {
                    return [int]$content.quota_percentage
                }
            } catch {
                continue
            }
        }
    }
    
    return $null
}

function Get-QuotaFromApiEndpoint {
    <#
    .SYNOPSIS
    Attempts to get quota from API endpoint if available
    #>
    
    $apiEndpoint = $env:IFLOW_API_ENDPOINT
    if (-not $apiEndpoint) {
        return $null
    }
    
    try {
        $response = Invoke-RestMethod -Uri "$apiEndpoint/quota" -Method Get -TimeoutSec 5
        
        if ($response.percentage) {
            return [int]$response.percentage
        }
        if ($response.remaining) {
            return [int]$response.remaining
        }
    } catch {
        return $null
    }
    
    return $null
}

function Get-CurrentQuota {
    <#
    .SYNOPSIS
    Main function to get current quota using multiple detection methods
    #>
    
    # Try each detection method in order
    $quota = Get-QuotaFromiFlowStatus
    if ($null -ne $quota) { return $quota }
    
    $quota = Get-QuotaFromEnvironment
    if ($null -ne $quota) { return $quota }
    
    $quota = Get-QuotaFromMetricsFile
    if ($null -ne $quota) { return $quota }
    
    $quota = Get-QuotaFromApiEndpoint
    if ($null -ne $quota) { return $quota }
    
    # Default to 100 if no method succeeds (assume unlimited)
    return 100
}

# =============================================================================
# Quota Status Management
# =============================================================================

function Update-QuotaStatus {
    param(
        [int]$Percentage,
        [string]$Status = "normal",
        [string]$Message = ""
    )
    
    $statusObj = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Percentage = $Percentage
        Status = $Status
        Message = $Message
        Available = if ($Percentage -ge 75) { "high" } elseif ($Percentage -ge 50) { "medium" } elseif ($Percentage -ge 25) { "low" } else { "critical" }
        Used = 100 - $Percentage
    }
    
    $statusObj | ConvertTo-Json | Out-File -FilePath $QUOTA_STATUS -Encoding UTF8
}

function Set-ShutdownFlag {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    @"
SHUTDOWN_REQUESTED=$timestamp
REASON=QUOTA_CRITICAL
QUOTA_PERCENTAGE=$quota
"@ | Out-File -FilePath $SHUTDOWN_FLAG -Encoding UTF8
    
    Write-Log "Shutdown flag set due to critical quota" "WARN"
}

# =============================================================================
# Notification Functions
# =============================================================================

function Send-QuotaWarning {
    param([int]$Percentage)
    
    Write-Log "QUOTA WARNING: $Percentage% remaining" "WARN"
    
    # Could integrate with notification systems here
    # e.g., Slack webhook, email, etc.
}

function Send-QuotaCritical {
    param([int]$Percentage)
    
    Write-Log "QUOTA CRITICAL: $Percentage% remaining - Initiating shutdown" "ERROR"
    
    # Could integrate with notification systems here
}

# =============================================================================
# Monitor Loop
# =============================================================================

function Start-QuotaMonitor {
    Write-Log "Starting quota monitor..."
    Write-Log "Check interval: $CheckInterval seconds"
    Write-Log "Critical threshold: $CriticalThreshold%"
    Write-Log "Warning threshold: $WarningThreshold%"
    
    $iteration = 0
    $consecutiveCriticalCount = 0
    $maxConsecutiveCritical = 3
    
    while ($true) {
        $iteration++
        
        # Get current quota
        $quota = Get-CurrentQuota
        
        Write-Log "Quota check #$iteration : $quota%"
        
        # Determine status
        $status = "normal"
        $message = ""
        
        if ($quota -le $CriticalThreshold) {
            $status = "critical"
            $message = "Quota critical - below $CriticalThreshold%"
            $consecutiveCriticalCount++
            
            Send-QuotaCritical -Percentage $quota
            
            # Require multiple consecutive critical readings to avoid false positives
            if ($consecutiveCriticalCount -ge $maxConsecutiveCritical) {
                Write-Log "Consecutive critical readings: $consecutiveCriticalCount - Setting shutdown flag" "ERROR"
                Set-ShutdownFlag
                Update-QuotaStatus -Percentage $quota -Status $status -Message $message
                
                # Trigger restart manager
                $restartManager = Join-Path $PROJECT_ROOT "restart-manager.ps1"
                if (Test-Path $restartManager) {
                    Start-Process -FilePath "pwsh" -ArgumentList "-File", $restartManager -WindowStyle Hidden
                }
                
                # Reset counter
                $consecutiveCriticalCount = 0
            }
        } elseif ($quota -le $WarningThreshold) {
            $status = "warning"
            $message = "Quota low - below $WarningThreshold%"
            $consecutiveCriticalCount = 0
            Send-QuotaWarning -Percentage $quota
        } else {
            $consecutiveCriticalCount = 0
        }
        
        # Update status file
        Update-QuotaStatus -Percentage $quota -Status $status -Message $message
        
        # Sleep before next check
        Start-Sleep -Seconds $CheckInterval
    }
}

# =============================================================================
# Main
# =============================================================================

function Main {
    Write-Log "============================================"
    Write-Log "Quota Monitor Starting"
    Write-Log "============================================"
    Write-Log "PID: $PID"
    
    # Ensure log directory exists
    if (-not (Test-Path $LOG_DIR)) {
        New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
    }
    
    # Initialize quota status
    Update-QuotaStatus -Percentage 100 -Status "initializing" -Message "Monitor starting"
    
    try {
        Start-QuotaMonitor
    } catch {
        Write-Log "Monitor error: $_" "ERROR"
        Update-QuotaStatus -Percentage 0 -Status "error" -Message $_
    }
}

Main
