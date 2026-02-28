#!/usr/bin/env pwsh
# Retry Logic Script - PowerShell Version
# ========================================
# Retry mechanism for failed operations

param(
    [Parameter(Mandatory=$true)]
    [scriptblock]$Operation,
    
    [int]$MaxRetries = 3,
    [int]$InitialDelay = 5,
    [double]$BackoffMultiplier = 2.0,
    [int]$MaxDelay = 60,
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = $SCRIPT_DIR
$LOG_DIR = Join-Path $PROJECT_ROOT "logs"
$RETRY_LOG = Join-Path $LOG_DIR "retry.log"

# =============================================================================
# Logging
# =============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [RETRY] [$Level] $Message"
    
    if ($Verbose -or $Level -eq "ERROR") {
        switch ($Level) {
            "ERROR" { Write-Host $logMessage -ForegroundColor Red }
            "WARN" { Write-Host $logMessage -ForegroundColor Yellow }
            "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
            default { Write-Host $logMessage -ForegroundColor Cyan }
        }
    }
    
    if (Test-Path $LOG_DIR) {
        Add-Content -Path $RETRY_LOG -Value $logMessage
    }
}

# =============================================================================
# Retry Functions
# =============================================================================

function Invoke-WithRetry {
    param(
        [scriptblock]$Operation,
        [int]$MaxRetries,
        [int]$InitialDelay,
        [double]$BackoffMultiplier,
        [int]$MaxDelay
    )
    
    $attempt = 0
    $delay = $InitialDelay
    $lastError = $null
    
    while ($attempt -lt $MaxRetries) {
        $attempt++
        
        Write-Log "Attempt $attempt of $MaxRetries"
        
        try {
            $result = & $Operation
            
            if ($attempt -gt 1) {
                Write-Log "Operation succeeded on attempt $attempt" "SUCCESS"
            }
            
            return @{
                Success = $true
                Result = $result
                Attempts = $attempt
            }
        } catch {
            $lastError = $_
            Write-Log "Attempt $attempt failed: $($_.Exception.Message)" "WARN"
            
            if ($attempt -lt $MaxRetries) {
                Write-Log "Waiting $delay seconds before retry..."
                Start-Sleep -Seconds $delay
                
                # Calculate next delay with exponential backoff
                $delay = [math]::Min([math]::Round($delay * $BackoffMultiplier), $MaxDelay)
            }
        }
    }
    
    Write-Log "All $MaxRetries attempts failed" "ERROR"
    
    return @{
        Success = $false
        Error = $lastError
        Attempts = $attempt
    }
}

# =============================================================================
# Common Retry Operations
# =============================================================================

function Invoke-GitOperationWithRetry {
    param(
        [string]$GitCommand,
        [int]$MaxRetries = 3
    )
    
    Write-Log "Executing Git command: $GitCommand"
    
    $result = Invoke-WithRetry -Operation {
        $output = Invoke-Expression $GitCommand 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Git command failed with exit code $LASTEXITCODE"
        }
        return $output
    } -MaxRetries $MaxRetries -InitialDelay 2 -BackoffMultiplier 2 -MaxDelay 30
    
    return $result
}

function Invoke-HttpWithRetry {
    param(
        [string]$Url,
        [string]$Method = "GET",
        [int]$Timeout = 30,
        [int]$MaxRetries = 3
    )
    
    Write-Log "HTTP $Method request to: $Url"
    
    $result = Invoke-WithRetry -Operation {
        $response = Invoke-WebRequest -Uri $Url -Method $Method -TimeoutSec $Timeout
        return $response
    } -MaxRetries $MaxRetries -InitialDelay 5 -BackoffMultiplier 2 -MaxDelay 60
    
    return $result
}

function Invoke-CommandWithRetry {
    param(
        [string]$Command,
        [int]$MaxRetries = 3,
        [int]$InitialDelay = 5
    )
    
    Write-Log "Executing command: $Command"
    
    $result = Invoke-WithRetry -Operation {
        $output = Invoke-Expression $Command 2>&1
        return $output
    } -MaxRetries $MaxRetries -InitialDelay $InitialDelay -BackoffMultiplier 2 -MaxDelay 60
    
    return $result
}

# =============================================================================
# Circuit Breaker Pattern
# =============================================================================

class CircuitBreaker {
    [int]$FailureThreshold
    [int]$ResetTimeout
    [int]$FailureCount = 0
    [datetime]$LastFailureTime
    [string]$State = "closed"  # closed, open, half-open
    
    CircuitBreaker([int]$failureThreshold, [int]$resetTimeout) {
        $this.FailureThreshold = $failureThreshold
        $this.ResetTimeout = $resetTimeout
    }
    
    [bool]CanExecute() {
        if ($this.State -eq "closed") {
            return $true
        }
        
        if ($this.State -eq "open") {
            $elapsed = (Get-Date) - $this.LastFailureTime
            if ($elapsed.TotalSeconds -ge $this.ResetTimeout) {
                $this.State = "half-open"
                return $true
            }
            return $false
        }
        
        # half-open state
        return $true
    }
    
    [void]RecordSuccess() {
        $this.FailureCount = 0
        $this.State = "closed"
    }
    
    [void]RecordFailure() {
        $this.FailureCount++
        $this.LastFailureTime = Get-Date
        
        if ($this.FailureCount -ge $this.FailureThreshold) {
            $this.State = "open"
        }
    }
}

function New-CircuitBreaker {
    param(
        [int]$FailureThreshold = 5,
        [int]$ResetTimeout = 60
    )
    
    return [CircuitBreaker]::new($FailureThreshold, $ResetTimeout)
}

function Invoke-WithCircuitBreaker {
    param(
        [scriptblock]$Operation,
        [CircuitBreaker]$CircuitBreaker
    )
    
    if (-not $CircuitBreaker.CanExecute()) {
        throw "Circuit breaker is open"
    }
    
    try {
        $result = & $Operation
        $CircuitBreaker.RecordSuccess()
        return $result
    } catch {
        $CircuitBreaker.RecordFailure()
        throw
    }
}

# =============================================================================
# Bulkhead Pattern (Concurrency Limiting)
# =============================================================================

class Bulkhead {
    [int]$MaxConcurrent
    [int]$CurrentCount = 0
    [System.Threading.Semaphore]$Semaphore
    
    Bulkhead([int]$maxConcurrent) {
        $this.MaxConcurrent = $maxConcurrent
        $this.Semaphore = [System.Threading.Semaphore]::new($maxConcurrent, $maxConcurrent)
    }
    
    [bool]TryEnter() {
        return $this.Semaphore.WaitOne(0)
    }
    
    [void]Enter([int]$timeoutMs) {
        if (-not $this.Semaphore.WaitOne($timeoutMs)) {
            throw "Bulkhead full - max concurrent executions reached"
        }
    }
    
    [void]Exit() {
        $this.Semaphore.Release()
    }
}

function New-Bulkhead {
    param([int]$MaxConcurrent = 5)
    
    return [Bulkhead]::new($MaxConcurrent)
}

function Invoke-WithBulkhead {
    param(
        [scriptblock]$Operation,
        [Bulkhead]$Bulkhead,
        [int]$TimeoutMs = 30000
    )
    
    try {
        $Bulkhead.Enter($TimeoutMs)
        $result = & $Operation
        return $result
    } finally {
        $Bulkhead.Exit()
    }
}

# =============================================================================
# Main Entry Point
# =============================================================================

function Main {
    # Ensure log directory exists
    if (-not (Test-Path $LOG_DIR)) {
        New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
    }
    
    Write-Log "Retry Logic Module Loaded"
    Write-Log "Max Retries: $MaxRetries"
    Write-Log "Initial Delay: $InitialDelay seconds"
    Write-Log "Backoff Multiplier: $BackoffMultiplier"
    Write-Log "Max Delay: $MaxDelay seconds"
    
    if ($Operation) {
        $result = Invoke-WithRetry -Operation $Operation -MaxRetries $MaxRetries -InitialDelay $InitialDelay -BackoffMultiplier $BackoffMultiplier -MaxDelay $MaxDelay
        
        if ($result.Success) {
            Write-Log "Operation completed successfully after $($result.Attempts) attempt(s)" "SUCCESS"
            Write-Output $result.Result
            exit 0
        } else {
            Write-Log "Operation failed after $($result.Attempts) attempt(s)" "ERROR"
            Write-Error $result.Error
            exit 1
        }
    }
}

# Only run main if this script is executed directly (not imported)
if ($MyInvocation.InvocationName -ne '.') {
    Main
}

# Export functions for module use
Export-ModuleMember -Function @(
    'Invoke-WithRetry',
    'Invoke-GitOperationWithRetry',
    'Invoke-HttpWithRetry',
    'Invoke-CommandWithRetry',
    'New-CircuitBreaker',
    'Invoke-WithCircuitBreaker',
    'New-Bulkhead',
    'Invoke-WithBulkhead'
)
