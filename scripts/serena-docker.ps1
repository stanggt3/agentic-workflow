#Requires -Version 5.1
<#
.SYNOPSIS
    Windows PowerShell wrapper for the Serena MCP container.
    Equivalent of scripts/serena-docker (bash).
.DESCRIPTION
    Mounts the current working directory into the Serena Docker container and
    starts the MCP server. Claude Code (or Codex) calls this script at
    invocation time, so (Get-Location) == the repo root being analysed.

    To upgrade the Serena version: update BASE_VERSION here AND the matching
    value in scripts/serena-docker (the bash version). setup.ps1 reads the
    version from the bash file as the single source of truth; keep them in sync.
.EXAMPLE
    # Typically called by Claude Code via MCP registration, not directly.
    # To test manually from a repo root:
    powershell -File "$HOME\.local\bin\serena-docker.ps1"
#>

$ErrorActionPreference = "Stop"

$RepoPath = (Get-Location).Path

# Sanitise repo name: replace non-alphanumeric (except - _ .) with '-'
$RepoName = [System.IO.Path]::GetFileName($RepoPath) -replace '[^a-zA-Z0-9\-_.]', '-'

$ContainerName = "serena-$RepoName"
$BaseVersion   = "latest"   # single source of truth for version — keep in sync with scripts/serena-docker

# ---------------------------------------------------------------------------
# Select image based on .serena/project.yml language declarations
# ---------------------------------------------------------------------------

$Image      = "serena-local:$BaseVersion"
$ProjectYml = Join-Path $RepoPath ".serena\project.yml"

if (Test-Path $ProjectYml) {
    $ymlContent = Get-Content $ProjectYml -Raw
    # Match lines like "  - csharp" (with optional leading whitespace)
    if ($ymlContent -match '(?m)^\s*-\s*csharp(\s|$)') {
        $Image = "serena-local:$BaseVersion-csharp"
    }
}

# ---------------------------------------------------------------------------
# Fail fast if the required image hasn't been built yet
# ---------------------------------------------------------------------------

$imageId = docker images -q $Image 2>$null
if (-not $imageId) {
    Write-Error "ERROR: $Image not found. Run setup.ps1 to build it."
    if ($Image -like "*-csharp") {
        Write-Error "       C# image is built separately. setup.ps1 handles this automatically."
    }
    exit 1
}

# ---------------------------------------------------------------------------
# Ensure Serena working directories exist
# ---------------------------------------------------------------------------

$serenaDirs = @(
    (Join-Path $RepoPath ".serena\cache"),
    (Join-Path $RepoPath ".serena\logs"),
    (Join-Path $RepoPath ".serena\memory")
)
foreach ($dir in $serenaDirs) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

# ---------------------------------------------------------------------------
# Build docker run arguments
# NOTE: Swift LSP bridge is macOS-only and is not implemented here.
# ---------------------------------------------------------------------------

$dockerArgs = @(
    "run",
    "--name", $ContainerName,
    "--rm", "-i",
    "-v", "${RepoPath}:/workspaces/projects/${RepoName}:ro",
    "-v", "${RepoPath}/.serena/project.yml:/workspaces/projects/${RepoName}/.serena/project.yml",
    "-v", "${RepoPath}/.serena/cache:/workspaces/projects/${RepoName}/.serena/cache",
    "-v", "${RepoPath}/.serena/logs:/workspaces/projects/${RepoName}/.serena/logs",
    "-v", "${RepoPath}/.serena/memory:/workspaces/projects/${RepoName}/.serena/memory",
    $Image,
    "serena", "start-mcp-server",
    "--context", "claude-code",
    "--project", "/workspaces/projects/$RepoName"
)

# ---------------------------------------------------------------------------
# Run — passes through stdin/stdout so the MCP JSON-RPC stream is transparent
# ---------------------------------------------------------------------------

& docker @dockerArgs
exit $LASTEXITCODE
