#!/usr/bin/env pwsh
# Ideate Worker Script - PowerShell Version
# ==========================================
# Automated feature brainstorming and ideation agent

param(
    [string]$Config = "iflow-ideate.yaml",
    [int]$MaxIterations = 100,
    [int]$IterationDelay = 120
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
$IDEA_HISTORY = Join-Path $PROJECT_ROOT "idea-history.json"

$WORKER_NAME = "ideate"
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
        default { Write-Host $logMessage -ForegroundColor Magenta }
    }
    
    Add-Content -Path $WORKER_LOG -Value $logMessage
}

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
# Feature Queue Management
# =============================================================================

function Get-FeatureQueue {
    if (-not (Test-Path $FEATURE_QUEUE)) { return @() }
    try {
        return Get-Content $FEATURE_QUEUE -Raw | ConvertFrom-Json
    } catch { return @() }
}

function Save-FeatureQueue {
    param([array]$Queue)
    $Queue | ConvertTo-Json -Depth 10 | Out-File -FilePath $FEATURE_QUEUE
}

function Add-FeatureToQueue {
    param([object]$Feature)
    $queue = @(Get-FeatureQueue)
    $queue += $Feature
    Save-FeatureQueue -Queue $queue
    Write-Log "Added feature to queue: $($Feature.Name)" "SUCCESS"
}

function Get-IdeaHistory {
    if (-not (Test-Path $IDEA_HISTORY)) { return @() }
    try {
        return Get-Content $IDEA_HISTORY -Raw | ConvertFrom-Json
    } catch { return @() }
}

function Save-IdeaToHistory {
    param([object]$Idea)
    $history = @(Get-IdeaHistory)
    $history += $Idea
    $history | ConvertTo-Json -Depth 10 | Out-File -FilePath $IDEA_HISTORY
}

# =============================================================================
# Project Analysis
# =============================================================================

function Get-ProjectInfo {
    $info = @{
        Name = ""
        Description = ""
        Type = "unknown"
        Languages = @()
        Frameworks = @()
        Features = @()
        Files = @()
        TODOs = @()
        Gaps = @()
    }
    
    # Get project name
    if (Test-Path "package.json") {
        $pkg = Get-Content "package.json" -Raw | ConvertFrom-Json
        $info.Name = $pkg.name
        $info.Description = $pkg.description
        $info.Languages += "JavaScript/TypeScript"
        
        # Detect frameworks
        if ($pkg.dependencies.PSObject.Properties.Name -contains "react") { $info.Frameworks += "React" }
        if ($pkg.dependencies.PSObject.Properties.Name -contains "next") { $info.Frameworks += "Next.js" }
        if ($pkg.dependencies.PSObject.Properties.Name -contains "express") { $info.Frameworks += "Express" }
        if ($pkg.dependencies.PSObject.Properties.Name -contains "vue") { $info.Frameworks += "Vue" }
        if ($pkg.devDependencies.PSObject.Properties.Name -contains "typescript") { $info.Languages += "TypeScript" }
    }
    
    if (Test-Path "requirements.txt") {
        $info.Languages += "Python"
        $reqs = Get-Content "requirements.txt"
        if ($reqs -match "django") { $info.Frameworks += "Django" }
        if ($reqs -match "flask") { $info.Frameworks += "Flask" }
        if ($reqs -match "fastapi") { $info.Frameworks += "FastAPI" }
    }
    
    # Determine project type
    if ($info.Frameworks -contains "React" -or $info.Frameworks -contains "Vue") { $info.Type = "frontend" }
    elseif ($info.Frameworks -contains "Express" -or $info.Frameworks -contains "Django") { $info.Type = "backend" }
    elseif ($info.Frameworks -contains "Next.js") { $info.Type = "fullstack" }
    
    return $info
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

function Find-TODOs {
    $files = Find-SourceFiles
    $todos = @()
    
    foreach ($file in $files) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }
        
        # Find TODOs, FIXMEs, HACKs
        $matches = [regex]::Matches($content, "(TODO|FIXME|HACK|XXX):\s*(.+)", "IgnoreCase")
        foreach ($match in $matches) {
            $todos += @{
                File = $file.FullName
                Type = $match.Groups[1].Value
                Text = $match.Groups[2].Value.Trim()
            }
        }
    }
    
    return $todos
}

function Find-FeatureGaps {
    $gaps = @()
    $files = Find-SourceFiles
    
    # Check for common missing features
    $hasAuth = $false
    $hasTesting = $false
    $hasValidation = $false
    $hasLogging = $false
    $hasCaching = $false
    $hasRateLimit = $false
    $hasI18n = $false
    
    foreach ($file in $files) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }
        
        if ($content -match "auth|login|password|token|jwt") { $hasAuth = $true }
        if ($content -match "test|spec|jest|mocha|pytest") { $hasTesting = $true }
        if ($content -match "validate|schema|joi|zod|yup") { $hasValidation = $true }
        if ($content -match "log|winston|pino|logger") { $hasLogging = $true }
        if ($content -match "cache|redis|memcached") { $hasCaching = $true }
        if ($content -match "rate.?limit|throttle") { $hasRateLimit = $true }
        if ($content -match "i18n|locale|translation|intl") { $hasI18n = $true }
    }
    
    if (-not $hasAuth) { $gaps += @{ Area = "Authentication"; Suggestion = "Add user authentication system" } }
    if (-not $hasTesting) { $gaps += @{ Area = "Testing"; Suggestion = "Add unit and integration tests" } }
    if (-not $hasValidation) { $gaps += @{ Area = "Validation"; Suggestion = "Add input validation" } }
    if (-not $hasLogging) { $gaps += @{ Area = "Logging"; Suggestion = "Add logging system" } }
    if (-not $hasCaching) { $gaps += @{ Area = "Caching"; Suggestion = "Add caching layer" } }
    if (-not $hasRateLimit) { $gaps += @{ Area = "Rate Limiting"; Suggestion = "Add API rate limiting" } }
    if (-not $hasI18n) { $gaps += @{ Area = "Internationalization"; Suggestion = "Add i18n support" } }
    
    return $gaps
}

function Get-RecentChanges {
    try {
        $log = git log --oneline -10 2>$null
        return $log
    } catch {
        return @()
    }
}

function Get-UserActivity {
    try {
        $issues = gh issue list --limit 5 2>$null
        return $issues
    } catch {
        return @()
    }
}

# =============================================================================
# Idea Generation
# =============================================================================

function Invoke-iFlowAgent {
    param(
        [string]$Prompt,
        [string]$Mode = "thinking"
    )
    
    Write-Log "Invoking iFlow agent with mode: $Mode"
    
    try {
        $promptFile = Join-Path $env:TEMP "iflow-prompt-$(Get-Random).txt"
        $Prompt | Out-File -FilePath $promptFile -Encoding UTF8
        
        $result = & iflow --mode $Mode --file $promptFile 2>&1
        
        Remove-Item $promptFile -Force -ErrorAction SilentlyContinue
        
        return $result
    } catch {
        Write-Log "iFlow invocation failed: $_" "ERROR"
        return $null
    }
}

function New-FeatureIdeas {
    Write-Log "Analyzing codebase for new feature ideas..."
    
    # Gather context
    $projectInfo = Get-ProjectInfo
    $todos = Find-TODOs
    $gaps = Find-FeatureGaps
    $recentChanges = Get-RecentChanges
    
    Write-Log "Found $($todos.Count) TODOs and $($gaps.Count) feature gaps"
    
    # Build analysis prompt
    $prompt = @"
You are a creative software architect analyzing a codebase for new feature opportunities.

PROJECT INFO:
Name: $($projectInfo.Name)
Type: $($projectInfo.Type)
Languages: $($projectInfo.Languages -join ', ')
Frameworks: $($projectInfo.Frameworks -join ', ')

DISCOVERED TODOs:
$($todos | ForEach-Object { "- [$($_.Type)] $($_.Text) in $($_.File)" } | Out-String)

FEATURE GAPS DETECTED:
$($gaps | ForEach-Object { "- $($_.Area): $($_.Suggestion)" } | Out-String)

RECENT CHANGES:
$($recentChanges -join "`n")

TASK:
Generate 3-5 innovative feature ideas that would improve this codebase. For each feature, provide:
1. Name - Short, descriptive name
2. Description - What it does (2-3 sentences)
3. Priority - "high", "medium", or "low"
4. Category - "enhancement", "new-feature", "optimization", "integration", or "ux"
5. Rationale - Why this feature matters
6. EstimatedEffort - "small", "medium", or "large"

Consider:
- User experience improvements
- Performance optimizations
- Security enhancements
- Developer experience
- Business value
- Technical debt reduction

Output in JSON array format:
[
  {
    "Name": "...",
    "Description": "...",
    "Priority": "...",
    "Category": "...",
    "Rationale": "...",
    "EstimatedEffort": "..."
  }
]
"@
    
    $result = Invoke-iFlowAgent -Prompt $prompt -Mode "thinking"
    
    if ($result) {
        try {
            # Try to parse JSON from result
            $jsonMatch = [regex]::Match($result, "\[[\s\S]*\]")
            if ($jsonMatch.Success) {
                $ideas = $jsonMatch.Value | ConvertFrom-Json
                Write-Log "Generated $($ideas.Count) feature ideas" "SUCCESS"
                return $ideas
            }
        } catch {
            Write-Log "Failed to parse ideas: $_" "ERROR"
        }
    }
    
    # Fallback: Generate from gaps
    Write-Log "Using fallback idea generation from gaps"
    $ideas = @()
    foreach ($gap in $gaps | Select-Object -First 3) {
        $ideas += @{
            Name = "$($gap.Area) System"
            Description = $gap.Suggestion
            Priority = "medium"
            Category = "enhancement"
            Rationale = "Missing critical functionality identified through codebase analysis"
            EstimatedEffort = "medium"
        }
    }
    
    return $ideas
}

function Add-IdeasToQueue {
    param([array]$Ideas)
    
    $existingQueue = Get-FeatureQueue
    $existingNames = $existingQueue | ForEach-Object { $_.Name }
    
    foreach ($idea in $Ideas) {
        # Skip if already in queue
        if ($idea.Name -in $existingNames) {
            Write-Log "Skipping duplicate idea: $($idea.Name)" "WARN"
            continue
        }
        
        # Add timestamp
        $idea | Add-Member -NotePropertyName "CreatedAt" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
        $idea | Add-Member -NotePropertyName "Status" -NotePropertyValue "pending" -Force
        
        Add-FeatureToQueue -Feature $idea
        Save-IdeaToHistory -Idea $idea
    }
}

# =============================================================================
# Main Worker Loop
# =============================================================================

function Invoke-WorkerLoop {
    Write-Log "Starting ideate worker loop..."
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
        
        # Check current queue size
        $queue = Get-FeatureQueue
        Write-Log "Current feature queue: $($queue.Count) items"
        
        # Only generate new ideas if queue is small
        if ($queue.Count -lt 5) {
            Update-Status "brainstorming"
            Write-Log "Generating new feature ideas..."
            
            $ideas = New-FeatureIdeas
            
            if ($ideas -and $ideas.Count -gt 0) {
                Add-IdeasToQueue -Ideas $ideas
                Write-Log "Added $($ideas.Count) new ideas to queue" "SUCCESS"
            }
        } else {
            Write-Log "Queue has sufficient items, skipping idea generation"
        }
        
        Update-Status "waiting"
        Write-Log "Sleeping for $IterationDelay seconds..."
        Start-Sleep -Seconds $IterationDelay
    }
    
    Update-Status "completed"
    Write-Log "Ideate worker completed"
}

# =============================================================================
# Main
# =============================================================================

function Main {
    Write-Log "============================================"
    Write-Log "Ideate Worker Starting"
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
    
    Write-Log "Ideate Worker Exiting"
}

Main
