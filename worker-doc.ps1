#!/usr/bin/env pwsh
# Documentation Worker Script - PowerShell Version
# =================================================
# Documentation generation and maintenance agent

param(
    [string]$Config = "iflow-doc.yaml",
    [int]$MaxIterations = 100,
    [int]$IterationDelay = 45
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = $SCRIPT_DIR
$LOG_DIR = Join-Path $PROJECT_ROOT "logs"
$SHUTDOWN_FLAG = Join-Path $PROJECT_ROOT "shutdown.flag"
$COMMIT_LOCK = Join-Path $PROJECT_ROOT "commit.lock"
$QUOTA_STATUS = Join-Path $PROJECT_ROOT "quota.status"

$WORKER_NAME = "doc"
$WORKER_PID = Join-Path $PROJECT_ROOT "worker-$WORKER_NAME.pid"
$WORKER_STATUS = Join-Path $LOG_DIR "worker-$WORKER_NAME-status.txt"
$WORKER_LOG = Join-Path $LOG_DIR "worker-$WORKER_NAME.log"

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
function Test-CommitLock { return Test-Path $COMMIT_LOCK }

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
# Documentation Analysis Functions
# =============================================================================

function Find-SourceFiles {
    $extensions = @("*.py", "*.js", "*.ts", "*.jsx", "*.tsx", "*.go", "*.java", "*.cs")
    $files = @()
    
    foreach ($ext in $extensions) {
        $found = Get-ChildItem -Path $PROJECT_ROOT -Filter $ext -Recurse -ErrorAction SilentlyContinue | 
            Where-Object { $_.FullName -notmatch "node_modules|venv|__pycache__|\.git|test|spec" }
        $files += $found
    }
    
    return $files
}

function Test-HasDocumentation {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return $false }
    
    # Check for various doc comment patterns
    $docPatterns = @(
        '""".*?"""',           # Python docstrings
        "'''.*?'''",           # Python docstrings (single quotes)
        '/\*\*[\s\S]*?\*/',    # JSDoc/JavaDoc
        '///.*',               # C# XML docs
        '//\s*@param',         # JS @param comments
        '//\s*@returns',       # JS @returns comments
        '#\s*@param',          # Python param comments
        '"""[^\n]*$',          # Incomplete docstrings
    )
    
    foreach ($pattern in $docPatterns) {
        if ($content -match $pattern) { return $true }
    }
    
    return $false
}

function Get-FunctionCount {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return 0 }
    
    $count = 0
    
    # Count various function definitions
    $count += ([regex]::Matches($content, "function\s+\w+")).Count
    $count += ([regex]::Matches($content, "def\s+\w+")).Count
    $count += ([regex]::Matches($content, "func\s+\w+")).Count
    $count += ([regex]::Matches($content, "public\s+\w+\s+\w+\s*\(")).Count
    $count += ([regex]::Matches($content, "private\s+\w+\s+\w+\s*\(")).Count
    $count += ([regex]::Matches($content, "const\s+\w+\s*=\s*\(")).Count
    $count += ([regex]::Matches($content, "const\s+\w+\s*=\s*async")).Count
    
    return $count
}

function Invoke-DocumentationAnalysis {
    Write-Log "Running documentation analysis..."
    
    $files = @(Find-SourceFiles)
    $analysis = @{
        TotalFiles = $files.Count
        UndocumentedFiles = @()
        IncompleteDocs = @()
        TotalFunctions = 0
        DocumentedFunctions = 0
    }
    
    foreach ($file in $files) {
        if (Test-ShutdownFlag) { break }
        
        $hasDocs = Test-HasDocumentation -FilePath $file.FullName
        $funcCount = Get-FunctionCount -FilePath $file.FullName
        $analysis.TotalFunctions += $funcCount
        
        if (-not $hasDocs -and $funcCount -gt 0) {
            $analysis.UndocumentedFiles += @{
                File = $file.FullName
                Functions = $funcCount
            }
        } elseif ($hasDocs) {
            $analysis.DocumentedFunctions += $funcCount
        }
    }
    
    return $analysis
}

function Test-ReadmeExists {
    $readmeFiles = @("README.md", "README.txt", "readme.md", "Readme.md")
    foreach ($readme in $readmeFiles) {
        if (Test-Path (Join-Path $PROJECT_ROOT $readme)) { return $true }
    }
    return $false
}

function Test-ApiDocsExist {
    $apiDocDirs = @("docs", "documentation", "api-docs", "apidocs")
    foreach ($dir in $apiDocDirs) {
        $path = Join-Path $PROJECT_ROOT $dir
        if (Test-Path $path) {
            $mdFiles = @(Get-ChildItem -Path $path -Filter "*.md" -ErrorAction SilentlyContinue)
            if ($mdFiles.Count -gt 0) { return $true }
        }
    }
    return $false
}

# =============================================================================
# Documentation Generation Functions
# =============================================================================

function New-ReadmeTemplate {
    $readmePath = Join-Path $PROJECT_ROOT "README.md"
    
    if (Test-Path $readmePath) {
        Write-Log "README.md already exists"
        return
    }
    
    $template = @"
# Project Name

## Description
Brief description of the project.

## Installation

``````bash
# Installation instructions
``````

## Usage

``````bash
# Usage examples
``````

## API Reference

### Main Functions

#### `functionName(param1, param2)`
Description of the function.

**Parameters:**
- `param1` (type): Description
- `param2` (type): Description

**Returns:**
- type: Description

## Contributing

Contributions are welcome! Please read the contributing guidelines.

## License

MIT License
"@
    
    $template | Out-File -FilePath $readmePath -Encoding UTF8
    Write-Log "Created README.md template" "SUCCESS"
}

function New-DocstringTemplate {
    param(
        [string]$FilePath,
        [string]$Language
    )
    
    $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return }
    
    $template = ""
    
    switch ($Language) {
        "python" {
            $template = @"
"""
Module description.

Functions:
    function_name: Description
"""

def function_name(param1, param2):
    \"\"\"
    Description of the function.
    
    Args:
        param1 (type): Description of param1.
        param2 (type): Description of param2.
    
    Returns:
        type: Description of return value.
    \"\"\"
    pass
"@
        }
        "javascript" {
            $template = @"
/**
 * Module description
 * @module moduleName
 */

/**
 * Description of the function.
 * @param {type} param1 - Description of param1.
 * @param {type} param2 - Description of param2.
 * @returns {type} Description of return value.
 */
function functionName(param1, param2) {}
"@
        }
    }
    
    return $template
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

# =============================================================================
# Main Worker Loop
# =============================================================================

function Invoke-WorkerLoop {
    Write-Log "Starting doc worker loop..."
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
        
        Update-Status "analyzing"
        
        # Check for README
        if (-not (Test-ReadmeExists)) {
            Write-Log "README.md not found, creating template"
            New-ReadmeTemplate
        }
        
        # Analyze documentation
        $analysis = Invoke-DocumentationAnalysis
        
        $docPercentage = if ($analysis.TotalFunctions -gt 0) {
            [math]::Round(($analysis.DocumentedFunctions / $analysis.TotalFunctions) * 100, 1)
        } else { 100 }
        
        Write-Log "Documentation coverage: $docPercentage%"
        Write-Log "Undocumented files: $($analysis.UndocumentedFiles.Count)"
        
        if ($analysis.UndocumentedFiles.Count -gt 0) {
            Update-Status "generating"
            
            foreach ($file in $analysis.UndocumentedFiles | Select-Object -First 5) {
                if (Test-ShutdownFlag) { break }
                
                Write-Log "Would generate docs for: $($file.File) ($($file.Functions) functions)"
                # Here we would invoke iFlow to generate documentation
            }
            
            New-GitCommit -Message "Documentation updates from iteration $iteration"
        }
        
        Update-Status "waiting"
        Start-Sleep -Seconds $IterationDelay
    }
    
    Update-Status "completed"
    Write-Log "Doc worker completed"
}

# =============================================================================
# Main
# =============================================================================

function Main {
    Write-Log "============================================"
    Write-Log "Documentation Worker Starting"
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
    
    Write-Log "Documentation Worker Exiting"
}

Main
