#!/usr/bin/env pwsh
# Quota Checker Script - PowerShell Version
# ==========================================
# One-shot quota check utility for use by other scripts

param(
    [switch]$Json,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = $SCRIPT_DIR
$QUOTA_STATUS = Join-Path $PROJECT_ROOT "quota.status"

# =============================================================================
# Quota Detection Methods
# =============================================================================

function Get-QuotaFromiFlowStatus {
    try {
        $statusOutput = & iflow status 2>&1
        
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
    if ($env:IFLOW_QUOTA_PERCENTAGE) {
        try {
            return [int]$env:IFLOW_QUOTA_PERCENTAGE
        } catch {
            return $null
        }
    }
    return $null
}

function Get-QuotaFromMetricsFile {
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
                if ($content.quota) { return [int]$content.quota }
                if ($content.remaining_quota) { return [int]$content.remaining_quota }
                if ($content.quota_percentage) { return [int]$content.quota_percentage }
            } catch {
                continue
            }
        }
    }
    return $null
}

function Get-QuotaFromStatusFile {
    if (-not (Test-Path $QUOTA_STATUS)) {
        return $null
    }
    
    try {
        $content = Get-Content $QUOTA_STATUS -Raw | ConvertFrom-Json
        return [int]$content.Percentage
    } catch {
        return $null
    }
}

function Get-CurrentQuota {
    $quota = Get-QuotaFromiFlowStatus
    if ($null -ne $quota) { return $quota }
    
    $quota = Get-QuotaFromEnvironment
    if ($null -ne $quota) { return $quota }
    
    $quota = Get-QuotaFromMetricsFile
    if ($null -ne $quota) { return $quota }
    
    $quota = Get-QuotaFromStatusFile
    if ($null -ne $quota) { return $quota }
    
    return 100
}

# =============================================================================
# Main
# =============================================================================

$quota = Get-CurrentQuota

if ($Json) {
    $result = @{
        Percentage = $quota
        Status = if ($quota -le 10) { "critical" } elseif ($quota -le 25) { "warning" } else { "normal" }
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    $result | ConvertTo-Json
} elseif (-not $Quiet) {
    Write-Host "Quota: $quota%"
}

# Exit with code based on quota level
if ($quota -le 10) {
    exit 2  # Critical
} elseif ($quota -le 25) {
    exit 1  # Warning
} else {
    exit 0  # Normal
}
