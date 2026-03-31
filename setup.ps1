#Requires -Version 5.1
<#
.SYNOPSIS
    Windows equivalent of setup.sh for the agentic-workflow toolkit.
.DESCRIPTION
    Installs skills (as directory junctions), settings, MCP config, safety hooks,
    MCP bridge, Serena Docker wrapper, and other components into ~/.claude/.
    Requires: Node.js/npm, Docker Desktop, Python 3.10+, git
    Optional: bash (Git Bash or WSL) for hook scripts to function
.EXAMPLE
    .\setup.ps1
    pwsh .\setup.ps1
#>

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir  = Join-Path $env:USERPROFILE ".claude"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Step { param([string]$Msg) Write-Host ""; Write-Host $Msg }
function Write-Info { param([string]$Msg) Write-Host "  $Msg" }

function Write-JsonFile {
    # Writes an object as UTF-8 JSON without BOM (PS 5.1 Set-Content adds BOM).
    param([string]$Path, [object]$Data)
    $json = $Data | ConvertTo-Json -Depth 100
    $enc  = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $json, $enc)
}

function Get-JunctionTarget {
    # Returns the target of a junction/symlink, or $null if not a link.
    param([string]$Path)
    $item = Get-Item $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    if ($item.LinkType -in @("Junction","SymbolicLink")) {
        # Target is stored as an array on PS 5.1; take first element
        return ($item.Target | Select-Object -First 1)
    }
    return $null
}

# ---------------------------------------------------------------------------
# Tool detection
# ---------------------------------------------------------------------------

# Locate Git Bash — prefer it over WSL bash (WSL bash fails if no distro is installed)
$HasBash = $false
$BashExe  = $null
$gitBashCandidates = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files (x86)\Git\bin\bash.exe",
    "C:\Git\bin\bash.exe"
)
foreach ($candidate in $gitBashCandidates) {
    if (Test-Path $candidate) { $BashExe = $candidate; $HasBash = $true; break }
}
if (-not $HasBash) {
    # Fall back to whatever 'git' ships — git --exec-path gives Git's libexec dir,
    # bash.exe lives two levels up in bin/
    $gitCmd = Get-Command "git" -ErrorAction SilentlyContinue
    if ($gitCmd) {
        $gitBin = Join-Path (Split-Path (Split-Path $gitCmd.Source)) "bin\bash.exe"
        if (Test-Path $gitBin) { $BashExe = $gitBin; $HasBash = $true }
    }
}
$HasNode   = $null -ne (Get-Command "node"   -ErrorAction SilentlyContinue)
$HasNpm    = $null -ne (Get-Command "npm"    -ErrorAction SilentlyContinue)
$HasDocker = $null -ne (Get-Command "docker" -ErrorAction SilentlyContinue)
$HasClaude = $null -ne (Get-Command "claude" -ErrorAction SilentlyContinue)
$HasCodex  = $null -ne (Get-Command "codex"  -ErrorAction SilentlyContinue)
$HasGit    = $null -ne (Get-Command "git"    -ErrorAction SilentlyContinue)

# ---------------------------------------------------------------------------
# Managed skills list (mirrors MANAGED_SKILLS in setup.sh)
# ---------------------------------------------------------------------------

$ManagedSkills = @(
    "review","postReview","addressReview","enhancePrompt","rootCause",
    "bugHunt","bugReport","shipRelease","syncDocs","weeklyRetro",
    "officeHours","productReview","archReview",
    "design-analyze","design-analyze-web","design-analyze-ios",
    "design-language",
    "design-evolve","design-evolve-web","design-evolve-ios",
    "design-mockup","design-mockup-web","design-mockup-ios",
    "design-implement","design-implement-web","design-implement-ios",
    "design-refine",
    "design-verify","design-verify-web","design-verify-ios",
    "verify-app","verify-web","verify-ios"
)

Write-Host "=== Agentic Workflow Setup ==="
Write-Host ""

# ---------------------------------------------------------------------------
# Helper: install or refresh a skill junction
# ---------------------------------------------------------------------------

function Install-Skill {
    param(
        [string]$SkillName,
        [string]$Target,
        [string]$Source
    )

    $target = $Target   # shadow param with local for clarity
    $item = Get-Item $target -Force -ErrorAction SilentlyContinue

    if ($null -ne $item -and $item.LinkType -in @("Junction","SymbolicLink")) {
        # It's already a link - check where it points
        $currentTarget = ($item.Target | Select-Object -First 1)

        if ($currentTarget -eq $Source) {
            Write-Info "$SkillName`: up to date"
        }
        elseif ($currentTarget -match [regex]::Escape("\agentic-workflow\") -or
                $currentTarget -match [regex]::Escape("-agentic-workflow-")) {
            # Previous agentic-workflow install - refresh
            Remove-Item $target -Force -Recurse
            New-Item -ItemType Junction -Path $target -Value $Source | Out-Null
            Write-Info "$SkillName`: refreshed (was: $currentTarget)"
        }
        else {
            # Collision with another toolkit
            Write-Host ""
            Write-Info "WARNING COLLISION: $SkillName"
            Write-Info "  Existing link points to: $currentTarget"
            Write-Info "  Our source is:           $Source"
            Write-Info "  This may be a different skill with the same name from another toolkit."
            $answer = Read-Host "  Replace with ours? (y/n)"
            if ($answer -eq "y") {
                Remove-Item $target -Force -Recurse
                New-Item -ItemType Junction -Path $target -Value $Source | Out-Null
                Write-Info "$SkillName`: replaced"
            }
            else {
                Write-Info "$SkillName`: skipped (keeping existing)"
            }
        }
    }
    elseif ($null -ne $item -and $item.PSIsContainer) {
        # Real directory (not a junction) - possible collision
        $skillMd = Join-Path $target "SKILL.md"
        if (Test-Path $skillMd) {
            $existingName = (Select-String -Path $skillMd -Pattern "^name:" |
                            Select-Object -First 1).Line -replace "^name:\s*",""
            if ($existingName -eq $SkillName) {
                Write-Host ""
                Write-Info "WARNING COLLISION: $SkillName"
                Write-Info "  A non-junction directory exists at: $target"
                Write-Info "  It contains a skill named '$existingName' - this appears to match ours."
            }
            else {
                Write-Host ""
                Write-Info "WARNING COLLISION: $SkillName"
                Write-Info "  A non-junction directory exists at: $target"
                Write-Info "  It contains a skill named '$existingName' - this does NOT match our '$SkillName'."
                Write-Info "  This is likely a DIFFERENT skill from another toolkit."
            }
        }
        else {
            Write-Host ""
            Write-Info "WARNING COLLISION: $SkillName"
            Write-Info "  A directory exists at: $target (no SKILL.md - unknown origin)"
        }
        $answer = Read-Host "  Back up and replace with junction? (y/n)"
        if ($answer -eq "y") {
            $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            Move-Item $target "$target.bak.$ts"
            New-Item -ItemType Junction -Path $target -Value $Source | Out-Null
            Write-Info "$SkillName`: backed up and linked"
        }
        else {
            Write-Info "$SkillName`: skipped (keeping existing directory)"
        }
    }
    elseif ($null -ne $item -and !$item.PSIsContainer) {
        Write-Info "$SkillName`: WARNING - a file (not directory) exists at $target, skipping"
    }
    else {
        New-Item -ItemType Junction -Path $target -Value $Source | Out-Null
        Write-Info "$SkillName`: linked"
    }
}

# ---------------------------------------------------------------------------
# Skills
# ---------------------------------------------------------------------------

Write-Host "Installing skills..."
New-Item -ItemType Directory -Path (Join-Path $ClaudeDir "skills") -Force | Out-Null

foreach ($skill in $ManagedSkills) {
    $target = Join-Path $ClaudeDir "skills\$skill"
    $source = Join-Path $ScriptDir "skills\$skill"
    Install-Skill -SkillName $skill -Target $target -Source $source
}

# ---------------------------------------------------------------------------
# Bootstrap skill
# ---------------------------------------------------------------------------

Write-Step "Installing bootstrap skill..."
Install-Skill `
    -SkillName "bootstrap" `
    -Target    (Join-Path $ClaudeDir "skills\bootstrap") `
    -Source    (Join-Path $ScriptDir "bootstrap")

# ---------------------------------------------------------------------------
# Clean up stale skills from previous versions
# ---------------------------------------------------------------------------

Write-Step "Checking for stale skills..."
$AllManaged = $ManagedSkills + @("bootstrap")

$skillsDir = Join-Path $ClaudeDir "skills"
if (Test-Path $skillsDir) {
    Get-ChildItem $skillsDir -Directory -Force | ForEach-Object {
        $skillName = $_.Name
        if ($AllManaged -notcontains $skillName) {
            $linkTarget = Get-JunctionTarget $_.FullName
            if ($null -ne $linkTarget) {
                if ($linkTarget -match [regex]::Escape("\agentic-workflow\") -or
                    $linkTarget -match [regex]::Escape("-agentic-workflow-")) {
                    Write-Host ""
                    Write-Info "WARNING STALE: $skillName -> $linkTarget"
                    Write-Info "  This skill was installed by a previous version of agentic-workflow"
                    Write-Info "  but is no longer in the current version."
                    $answer = Read-Host "  Remove it? (y/n)"
                    if ($answer -eq "y") {
                        Remove-Item $_.FullName -Force -Recurse
                        Write-Info "$skillName`: removed"
                    }
                    else {
                        Write-Info "$skillName`: kept"
                    }
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

Write-Step "Installing settings..."
$SettingsFile = Join-Path $ClaudeDir "settings.json"
if (Test-Path $SettingsFile) {
    Write-Info "settings.json already exists."
    Write-Info "Current file will NOT be overwritten."
    Write-Info "Compare manually: diff `"$SettingsFile`" `"$ScriptDir\config\settings.json`""
}
else {
    Copy-Item "$ScriptDir\config\settings.json" $SettingsFile
    Write-Info "settings.json: copied"
}

# ---------------------------------------------------------------------------
# Statusline
# ---------------------------------------------------------------------------

Write-Step "Installing statusline..."
Copy-Item "$ScriptDir\config\statusline.sh" "$ClaudeDir\statusline.sh"
Write-Info "statusline script installed"
Write-Info "Note: statusline.sh requires bash (WSL or Git Bash) to function on Windows."

# Merge statusLine into existing settings.json if absent
if (Test-Path $SettingsFile) {
    $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json

    if (-not $settings.PSObject.Properties["statusLine"]) {
        $settings | Add-Member -MemberType NoteProperty -Name "statusLine" -Value (
            [PSCustomObject]@{ type = "command"; command = "~/.claude/statusline.sh" }
        )
        Write-JsonFile -Path $SettingsFile -Data $settings
        Write-Info "statusLine config added to existing settings.json"
    }

    # Merge Stop hook if not present
    if (-not ($settings.PSObject.Properties["hooks"]) -or
        -not ($settings.hooks.PSObject.Properties["Stop"])) {

        if (-not $settings.PSObject.Properties["hooks"]) {
            $settings | Add-Member -MemberType NoteProperty -Name "hooks" -Value ([PSCustomObject]@{})
        }
        $stopHook = @(
            [PSCustomObject]@{
                hooks = @(
                    [PSCustomObject]@{
                        type    = "command"
                        command = 'SHELL_PID=$(cat "$HOME/.claude/shell_pid" 2>/dev/null); [ -n "$SHELL_PID" ] && kill -WINCH "$SHELL_PID" 2>/dev/null; sleep 0.05; true'
                    }
                )
            }
        )
        $settings.hooks | Add-Member -MemberType NoteProperty -Name "Stop" -Value $stopHook
        Write-JsonFile -Path $SettingsFile -Data $settings
        Write-Info "hooks.Stop added to existing settings.json"
    }

    # Merge PreToolUse hook if not present
    $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json  # reload after writes
    if (-not ($settings.PSObject.Properties["hooks"]) -or
        -not ($settings.hooks.PSObject.Properties["PreToolUse"])) {

        if (-not $settings.PSObject.Properties["hooks"]) {
            $settings | Add-Member -MemberType NoteProperty -Name "hooks" -Value ([PSCustomObject]@{})
        }
        $ptuHook = @(
            [PSCustomObject]@{
                matcher = ".*"
                hooks   = @(
                    [PSCustomObject]@{
                        type    = "command"
                        command = 'SHELL_PID=$(cat "$HOME/.claude/shell_pid" 2>/dev/null); [ -n "$SHELL_PID" ] && kill -WINCH "$SHELL_PID" 2>/dev/null; true'
                    }
                )
            }
        )
        $settings.hooks | Add-Member -MemberType NoteProperty -Name "PreToolUse" -Value $ptuHook
        Write-JsonFile -Path $SettingsFile -Data $settings
        Write-Info "hooks.PreToolUse added to existing settings.json"
    }
}

# ---------------------------------------------------------------------------
# Safety hooks
# ---------------------------------------------------------------------------

Write-Step "Installing safety hooks..."
$HooksDir = Join-Path $ClaudeDir "hooks"
New-Item -ItemType Directory -Path $HooksDir -Force | Out-Null

Get-ChildItem "$ScriptDir\config\hooks\*.sh" | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $HooksDir $_.Name)
    Write-Info "$($_.Name): installed"
}

if (-not $HasBash) {
    Write-Info "WARNING: bash not found in PATH."
    Write-Info "  Hook scripts are bash scripts. Install Git Bash or WSL so they can run."
    Write-Info "  Hook commands will be registered as 'bash ~/.claude/hooks/<name>.sh'."
    Write-Info "  Without bash, Claude Code will fail to execute them."
}

# Build hook command prefix: use Git Bash path when available, plain path otherwise
$HookPrefix = if ($HasBash) { "`"$BashExe`" " } else { "" }

# Compute MSYS2 absolute path for the hooks dir so hook commands work when Claude Code
# invokes bash via cmd.exe (where ~ is NOT expanded by bash receiving it as a path argument)
# e.g. C:\Users\Randy\.claude\hooks → /c/Users/Randy/.claude/hooks
$HooksMsysPath = "/" + $HooksDir.Substring(0, 1).ToLower() + $HooksDir.Substring(2).Replace('\', '/')

# Merge safety hooks into settings.json (idempotent replace of Bash matcher)
if (Test-Path $SettingsFile) {
    $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json

    if (-not $settings.PSObject.Properties["hooks"]) {
        $settings | Add-Member -MemberType NoteProperty -Name "hooks" -Value ([PSCustomObject]@{})
    }

    $bashEntry = [PSCustomObject]@{
        matcher = "Bash"
        hooks   = @(
            [PSCustomObject]@{ type = "command"; command = "${HookPrefix}${HooksMsysPath}/block-destructive.sh" },
            [PSCustomObject]@{ type = "command"; command = "${HookPrefix}${HooksMsysPath}/block-push-main.sh" },
            [PSCustomObject]@{ type = "command"; command = "${HookPrefix}${HooksMsysPath}/detect-secrets.sh" },
            [PSCustomObject]@{ type = "command"; command = "${HookPrefix}${HooksMsysPath}/rtk-rewrite.sh" }
        )
    }

    # Replace any existing Bash matcher, add ours
    $existingPtu = @()
    if ($settings.hooks.PSObject.Properties["PreToolUse"]) {
        $existingPtu = @(@($settings.hooks.PreToolUse) | Where-Object { $_.matcher -ne "Bash" })
    }
    $newPtu = $existingPtu + @($bashEntry)

    if ($settings.hooks.PSObject.Properties["PreToolUse"]) {
        $settings.hooks.PreToolUse = $newPtu
    }
    else {
        $settings.hooks | Add-Member -MemberType NoteProperty -Name "PreToolUse" -Value $newPtu
    }

    Write-JsonFile -Path $SettingsFile -Data $settings
    Write-Info "hooks.PreToolUse: Bash safety hooks installed (idempotent replace)"

    # git-context SessionStart hook
    $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json
    $hasGitCtx = $false
    if ($settings.hooks.PSObject.Properties["SessionStart"]) {
        foreach ($entry in @($settings.hooks.SessionStart)) {
            foreach ($hook in @($entry.hooks)) {
                if ($hook.command -match "git-context") { $hasGitCtx = $true }
            }
        }
    }
    if (-not $hasGitCtx) {
        $gitCtxEntry = [PSCustomObject]@{
            hooks = @([PSCustomObject]@{
                type    = "command"
                command = "${HookPrefix}${HooksMsysPath}/git-context.sh"
            })
        }
        if ($settings.hooks.PSObject.Properties["SessionStart"]) {
            $settings.hooks.SessionStart = @($settings.hooks.SessionStart) + @($gitCtxEntry)
        }
        else {
            $settings.hooks | Add-Member -MemberType NoteProperty -Name "SessionStart" -Value @($gitCtxEntry)
        }
        Write-JsonFile -Path $SettingsFile -Data $settings
        Write-Info "hooks.SessionStart: git-context added"
    }

    # bridge-context SessionStart hook
    $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json
    $hasBridgeCtx = $false
    if ($settings.hooks.PSObject.Properties["SessionStart"]) {
        foreach ($entry in @($settings.hooks.SessionStart)) {
            foreach ($hook in @($entry.hooks)) {
                if ($hook.command -match "bridge-context") { $hasBridgeCtx = $true }
            }
        }
    }
    if (-not $hasBridgeCtx) {
        $bridgeCtxEntry = [PSCustomObject]@{
            hooks = @([PSCustomObject]@{
                type    = "command"
                command = "${HookPrefix}${HooksMsysPath}/bridge-context.sh"
            })
        }
        if ($settings.hooks.PSObject.Properties["SessionStart"]) {
            $settings.hooks.SessionStart = @($settings.hooks.SessionStart) + @($bridgeCtxEntry)
        }
        else {
            $settings.hooks | Add-Member -MemberType NoteProperty -Name "SessionStart" -Value @($bridgeCtxEntry)
        }
        Write-JsonFile -Path $SettingsFile -Data $settings
        Write-Info "hooks.SessionStart: bridge-context added"
    }
}

# ---------------------------------------------------------------------------
# Shell integration (terminal width sync for statusline)
# ---------------------------------------------------------------------------

Write-Step "Installing shell integration..."

$ShellIntegrationFile = Join-Path $ClaudeDir "shell-integration.sh"
$ShellIntegrationContent = @'
# Claude Code shell integration - written by agentic-workflow setup.ps1
# Keeps ~/.claude/terminal_width updated so statusline.sh can read the actual
# terminal width. Claude Code subprocesses cannot access /dev/tty or $COLUMNS,
# so the interactive shell (which always has the correct value) writes it here.
#
# Also writes ~/.claude/shell_pid so Claude Code hooks can send SIGWINCH to
# this shell, triggering a width update mid-session when the window is resized.

_claude_update_width() {
  printf '%s\n' "$$" > "$HOME/.claude/shell_pid"
  local width="${COLUMNS:-$(tput cols 2>/dev/null)}"
  [ -n "$width" ] && [ "$width" -gt 0 ] 2>/dev/null && \
    printf '%s\n' "$width" > "$HOME/.claude/terminal_width"
}

if [ -n "$ZSH_VERSION" ]; then
  autoload -U add-zsh-hook 2>/dev/null && add-zsh-hook precmd _claude_update_width
  trap '_claude_update_width' WINCH
elif [ -n "$BASH_VERSION" ]; then
  [[ "$PROMPT_COMMAND" != *"_claude_update_width"* ]] && \
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_claude_update_width"
  trap '_claude_update_width' WINCH
fi

_claude_update_width
'@

$existing = if (Test-Path $ShellIntegrationFile) { Get-Content $ShellIntegrationFile -Raw } else { "" }
if ($existing.Trim() -eq $ShellIntegrationContent.Trim()) {
    Write-Info "shell-integration.sh: already up to date (skipped)"
}
else {
    $enc = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($ShellIntegrationFile, $ShellIntegrationContent, $enc)
    Write-Info "shell-integration.sh: written (for use in WSL/Git Bash sessions)"
}

Write-Info "Note: .zshrc/.bashrc integration is not applicable on Windows."
Write-Info "  Source ~/.claude/shell-integration.sh in your WSL or Git Bash profile to enable width sync."

# Write terminal width from the current PowerShell console
try {
    $currentWidth = $Host.UI.RawUI.WindowSize.Width
    if ($currentWidth -gt 0) {
        $enc = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText((Join-Path $ClaudeDir "terminal_width"), "$currentWidth`n", $enc)
        Write-Info "terminal_width initialized: $currentWidth cols"
    }
}
catch {
    Write-Info "terminal_width: could not determine (non-fatal)"
}

# Write current PowerShell PID for any hook that needs it
try {
    $enc = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $ClaudeDir "shell_pid"), "$PID`n", $enc)
    Write-Info "shell_pid: written ($PID)"
}
catch { <# non-fatal #> }

# ---------------------------------------------------------------------------
# MCP Config
# ---------------------------------------------------------------------------

Write-Step "Installing MCP config..."
$McpFile = Join-Path $ClaudeDir "mcp.json"
if (Test-Path $McpFile) {
    Write-Info "mcp.json already exists."
    Write-Info "Current file will NOT be overwritten."
    Write-Info "Compare manually: diff `"$McpFile`" `"$ScriptDir\config\mcp.json`""
}
else {
    Copy-Item "$ScriptDir\config\mcp.json" $McpFile
    Write-Info "mcp.json: copied"
}

# ---------------------------------------------------------------------------
# MCP Bridge: Install, Build, Register
# ---------------------------------------------------------------------------

Write-Step "Installing MCP bridge..."
$BridgeDir = Join-Path $ScriptDir "mcp-bridge"

if (Test-Path "$BridgeDir\package.json") {
    if (-not $HasNpm) {
        Write-Info "WARNING: npm not found. Skipping MCP bridge build."
        Write-Info "  Install Node.js from https://nodejs.org then re-run setup.ps1"
    }
    else {
        Push-Location $BridgeDir
        try {
            npm install
            npm run build
            Write-Info "MCP bridge: built successfully"
        }
        catch {
            Write-Info "WARNING: MCP bridge build failed: $_"
        }
        finally {
            Pop-Location
        }
    }
}
else {
    Write-Info "MCP bridge: package.json not found, skipping"
}

# Register with Claude Code
Write-Step "Registering MCP bridge with Claude Code..."
if ($HasClaude) {
    $mcpList = & claude mcp list 2>&1
    if ($mcpList -match "agentic-bridge") {
        Write-Info "agentic-bridge: already registered in Claude Code"
    }
    else {
        & claude mcp add --scope user agentic-bridge -- node "$BridgeDir\dist\mcp.js"
        Write-Info "agentic-bridge: registered in Claude Code"
    }
}
else {
    Write-Info "claude CLI not found, skipping Claude Code registration"
}

# Register with Codex
Write-Step "Registering MCP bridge with Codex..."
if ($HasCodex) {
    $codexList = & codex mcp list 2>&1
    if ($codexList -match "agentic-bridge") {
        Write-Info "agentic-bridge: already registered in Codex"
    }
    else {
        & codex mcp add agentic-bridge -- node "$BridgeDir\dist\mcp.js"
        Write-Info "agentic-bridge: registered in Codex"
    }
}
else {
    Write-Info "codex CLI not found, skipping Codex registration"
}

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

Write-Step "Installing UI dependencies..."
$UiDir = Join-Path $ScriptDir "ui"
if (Test-Path "$UiDir\package.json") {
    if (-not $HasNpm) {
        Write-Info "WARNING: npm not found. Skipping UI install."
    }
    else {
        Push-Location $UiDir
        try {
            npm install
            Write-Info "UI: dependencies installed"
        }
        catch {
            Write-Info "WARNING: UI npm install failed: $_"
        }
        finally {
            Pop-Location
        }
    }
}
else {
    Write-Info "UI: package.json not found, skipping"
}

# ---------------------------------------------------------------------------
# Serena MCP
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "=== Serena prerequisites ==="

if (-not $HasDocker) {
    Write-Error "FATAL: Docker not installed. Install Docker Desktop and re-run setup.ps1."
    exit 1
}

# Derive version from committed bash wrapper (single source of truth)
$SerenaDockerBash = Join-Path $ScriptDir "scripts\serena-docker"
$SerenaVersion = ""
if (Test-Path $SerenaDockerBash) {
    $versionLine = Select-String -Path $SerenaDockerBash -Pattern "^BASE_VERSION=" |
                   Select-Object -First 1
    if ($versionLine) {
        $SerenaVersion = $versionLine.Line -replace '^BASE_VERSION="','' -replace '".*',''
    }
}
if (-not $SerenaVersion) {
    Write-Error "FATAL: Could not parse BASE_VERSION from scripts/serena-docker"
    exit 1
}

# Build Serena base image
Write-Host "=== Building Serena base image (TS + Python) ==="
$imageId = docker images -q "serena-local:${SerenaVersion}" 2>$null
if (-not $imageId) {
    Write-Host "Building serena-local:${SerenaVersion} (~5 min)..."
    docker build `
        --pull `
        --progress plain `
        --build-arg "BASE_TAG=${SerenaVersion}" `
        -t "serena-local:${SerenaVersion}" `
        -f (Join-Path $ScriptDir "Dockerfile.serena") `
        $ScriptDir
    if ($LASTEXITCODE -ne 0) { Write-Error "FATAL: Base image build failed."; exit 1 }
    Write-Host "Built serena-local:${SerenaVersion}"
}
else {
    Write-Host "serena-local:${SerenaVersion} already exists, skipping"
}

# C# extension image (opt-in)
Write-Host ""
Write-Host "=== Building Serena C# extension image (opt-in) ==="
$buildCsharp = ($env:BUILD_CSHARP -eq "1")
if (-not $buildCsharp) {
    $csFound = Get-ChildItem $ScriptDir -Recurse -Include "*.csproj","*.cs" -ErrorAction SilentlyContinue |
               Select-Object -First 1
    if ($csFound) { $buildCsharp = $true }
}
if ($buildCsharp) {
    $csharpId = docker images -q "serena-local:${SerenaVersion}-csharp" 2>$null
    if (-not $csharpId) {
        Write-Host "Building serena-local:${SerenaVersion}-csharp (~15 min, .NET SDK download)..."
        docker build `
            --pull `
            --progress plain `
            --build-arg "LOCAL_TAG=${SerenaVersion}" `
            -t "serena-local:${SerenaVersion}-csharp" `
            -f (Join-Path $ScriptDir "Dockerfile.serena-csharp") `
            $ScriptDir
        if ($LASTEXITCODE -ne 0) { Write-Error "FATAL: C# image build failed."; exit 1 }
        Write-Host "Built serena-local:${SerenaVersion}-csharp"
    }
    else {
        Write-Host "serena-local:${SerenaVersion}-csharp already exists, skipping"
    }
}
else {
    Write-Host "=== Skipping C# Serena image (no .csproj/.cs found) ==="
    Write-Host "To build later, run: `$env:BUILD_CSHARP=`"1`"; .\setup.ps1"
}

# Swift image - skip on Windows (macOS only)
Write-Host ""
Write-Host "=== Skipping Swift Serena image (macOS only) ==="

# Install serena-docker wrappers
Write-Host "=== Installing serena-docker wrapper ==="
$LocalBinDir = Join-Path $env:USERPROFILE ".local\bin"
New-Item -ItemType Directory -Path $LocalBinDir -Force | Out-Null

# Copy the bash script (usable under WSL)
Copy-Item $SerenaDockerBash (Join-Path $LocalBinDir "serena-docker") -Force
Write-Info "serena-docker (bash): copied to $LocalBinDir"

# Install the PowerShell wrapper (scripts/serena-docker.ps1 -> ~/.local/bin/serena-docker.ps1)
$SerenaPsSource = Join-Path $ScriptDir "scripts\serena-docker.ps1"
$SerenaPsDest   = Join-Path $LocalBinDir "serena-docker.ps1"
if (Test-Path $SerenaPsSource) {
    Copy-Item $SerenaPsSource $SerenaPsDest -Force
    Write-Info "serena-docker.ps1: installed to $LocalBinDir"
}
else {
    Write-Info "WARNING: scripts\serena-docker.ps1 not found - skipping PowerShell wrapper install"
}

# Check PATH
$userPath = [System.Environment]::GetEnvironmentVariable("PATH","User")
if ($userPath -notmatch [regex]::Escape($LocalBinDir)) {
    Write-Host ""
    Write-Host "WARN: $LocalBinDir is not in your PATH."
    Write-Host "  To add it permanently, run:"
    Write-Host "    `$env:PATH += `";$LocalBinDir`""
    Write-Host "    [System.Environment]::SetEnvironmentVariable('PATH', `$env:PATH, 'User')"
}

# Register Serena with Claude Code (using PowerShell wrapper)
Write-Host "=== Registering Serena MCP (global) ==="
if ($HasClaude) {
    $mcpListSerena = & claude mcp list 2>&1
    if ($mcpListSerena -match "serena") {
        Write-Info "serena: already registered in Claude Code"
    }
    else {
        & claude mcp add --scope user serena -- powershell -File $SerenaPsDest 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARN: Serena registration failed (claude CLI not found or conflict)"
        }
        else {
            Write-Info "serena: registered with Claude Code"
        }
    }
}
else {
    Write-Info "claude CLI not found, skipping Serena registration"
}

# XcodeBuildMCP - macOS only
Write-Host "=== Skipping XcodeBuildMCP (macOS only) ==="

# ---------------------------------------------------------------------------
# Security check
# ---------------------------------------------------------------------------

Write-Host "=== Security check ==="
$localSettings = Join-Path $env:USERPROFILE ".claude\settings.local.json"
if (Test-Path $localSettings) {
    $content = Get-Content $localSettings -Raw
    if ($content -match "Users\\$([regex]::Escape($env:USERNAME))\\\*\*" -or
        $content -match "Users/$([regex]::Escape($env:USERNAME))/\*\*") {
        Write-Host "WARN: Broad Read rule detected in settings.local.json - narrow to repos\**, .claude\**, .agentic-workflow\**"
    }
}

# ---------------------------------------------------------------------------
# Claude Code Plugins
# ---------------------------------------------------------------------------

Write-Step "Installing Claude Code plugins..."

if ($HasClaude) {
    $Marketplaces = @(
        "anthropics/claude-plugins-official",
        "VoltAgent/awesome-claude-code-subagents",
        "EveryInc/compound-engineering-plugin"
    )
    foreach ($repo in $Marketplaces) {
        $name = Split-Path $repo -Leaf
        $list = & claude plugins marketplace list 2>&1
        if ($list -match [regex]::Escape($name)) {
            Write-Info "marketplace $name`: already added"
        }
        else {
            $r = & claude plugins marketplace add "$repo" 2>&1
            if ($LASTEXITCODE -eq 0) { Write-Info "marketplace $name`: added" }
            else                     { Write-Info "marketplace $name`: failed to add (non-fatal)" }
        }
    }

    $Plugins = @(
        "github@claude-plugins-official",
        "superpowers@claude-plugins-official",
        "compound-engineering@compound-engineering-plugin",
        "playwright@claude-plugins-official"
    )
    foreach ($plugin in $Plugins) {
        $list = & claude plugins list 2>&1
        if ($list -match [regex]::Escape($plugin)) {
            Write-Info "plugin $plugin`: already installed"
        }
        else {
            $r = & claude plugins install $plugin 2>&1
            if ($LASTEXITCODE -eq 0) { Write-Info "plugin $plugin`: installed" }
            else                     { Write-Info "plugin $plugin`: failed to install (non-fatal)" }
        }
    }
}
else {
    Write-Info "claude CLI not found, skipping plugin installation"
}

# ---------------------------------------------------------------------------
# Dembrandt CLI
# ---------------------------------------------------------------------------

Write-Step "Installing Dembrandt CLI..."
$DembrandtVersion = "0.7.0"
$hasDemo = Get-Command "dembrandt" -ErrorAction SilentlyContinue
if ($hasDemo) {
    $demoVer = & dembrandt --version 2>$null
    Write-Info "dembrandt: already installed ($demoVer)"
}
else {
    if (-not $HasNpm) {
        Write-Info "npm not found - skipping dembrandt (install manually: npm install -g dembrandt)"
    }
    else {
        $r = & npm install -g "dembrandt@$DembrandtVersion" 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Info "dembrandt: installed globally ($DembrandtVersion)" }
        else                     { Write-Info "dembrandt: failed to install (non-fatal, install manually: npm install -g dembrandt)" }
    }
}

# ---------------------------------------------------------------------------
# Impeccable Skills
# ---------------------------------------------------------------------------

Write-Step "Installing Impeccable skills..."
$ImpeccableVersion  = "d6b1a56bc5b79e9375be0f8508b4daa1678fb058"
$ImpeccableDir      = Join-Path $env:USERPROFILE ".claude\impeccable-cache"
$ImpeccableSkillsSrc = Join-Path $ImpeccableDir "dist\claude-code"

if (Test-Path $ImpeccableSkillsSrc) {
    Write-Info "impeccable: cache exists, checking for updates..."
    if ($HasGit) {
        Push-Location $ImpeccableDir
        try {
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
            git fetch --quiet origin 2>&1 | Out-Null
            git checkout --quiet $ImpeccableVersion 2>&1 | Out-Null
            $ErrorActionPreference = $prev
        }
        catch {
            Write-Info "Warning: Could not update Impeccable cache. Using existing version."
        }
        finally { Pop-Location }
    }
}
else {
    if (-not $HasGit) {
        Write-Info "git not found - skipping Impeccable clone"
        $ImpeccableSkillsSrc = ""
    }
    else {
        Write-Info "impeccable: cloning pbakaus/impeccable..."
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
        git clone --quiet https://github.com/pbakaus/impeccable.git $ImpeccableDir 2>&1 | Out-Null
        $ErrorActionPreference = $prev
        if ($LASTEXITCODE -eq 0) {
            Push-Location $ImpeccableDir
            git checkout $ImpeccableVersion 2>&1 | Out-Null
            Pop-Location
        }
        else {
            Write-Info "impeccable: failed to clone (non-fatal)"
            $ImpeccableSkillsSrc = ""
        }
    }
}

if ($ImpeccableSkillsSrc -and (Test-Path $ImpeccableSkillsSrc)) {
    Get-ChildItem $ImpeccableSkillsSrc -Directory | ForEach-Object {
        $skillName = $_.Name
        $targetPath = Join-Path $ClaudeDir "skills\$skillName"
        if (Test-Path $targetPath) {
            $existing = Get-Item $targetPath -Force
            if ($existing.LinkType) { Remove-Item $targetPath -Force -Recurse }
            else                    { Remove-Item $targetPath -Recurse -Force }
        }
        Copy-Item $_.FullName $targetPath -Recurse
        Write-Info "impeccable/$skillName`: installed"
    }
}
else {
    Write-Info "impeccable: skipped (source not available)"
}

# ---------------------------------------------------------------------------
# rtk
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "=== Installing rtk ==="
$hasRtk = Get-Command "rtk" -ErrorAction SilentlyContinue
if ($hasRtk) {
    $rtkVer = & rtk --version 2>$null
    Write-Info "rtk: already installed ($rtkVer)"
}
else {
    $rtkInstallUrl = "https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh"
    if ($HasBash) {
        Write-Info "Installing rtk via curl installer (bash)..."
        & $BashExe -c "curl -fsSL $rtkInstallUrl | sh"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARN: rtk installation failed (non-fatal)."
            Write-Host "  Install manually: visit https://github.com/rtk-ai/rtk for a Windows installer"
        }
        $hasRtkAfter = Get-Command "rtk" -ErrorAction SilentlyContinue
        if (-not $hasRtkAfter) {
            Write-Host "WARN: rtk not found on PATH after installation."
            Write-Host "  It may have been installed to ~/.local/bin - ensure that is in your PATH."
        }
        else {
            Write-Info "rtk: installed"
        }
    }
    else {
        Write-Host "WARN: bash not found. Cannot run the rtk curl installer automatically."
        Write-Host "  Install rtk manually using one of:"
        Write-Host "    winget install rtk             (if available)"
        Write-Host "    scoop install rtk              (if available)"
        Write-Host "    or visit https://github.com/rtk-ai/rtk for a Windows installer"
        Write-Host "  Re-run setup.ps1 after installing rtk."
    }
}

# ---------------------------------------------------------------------------
# headroom
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "=== Installing headroom ==="

# Find Python 3.10+
$HeadroomPython = $null
foreach ($pyCmd in @("python3.13","python3.12","python3.11","python3.10","python3","python")) {
    $pyObj = Get-Command $pyCmd -ErrorAction SilentlyContinue
    if ($pyObj) {
        try {
            $pyMajor = & $pyCmd -c "import sys; print(sys.version_info.major)" 2>$null
            $pyMinor = & $pyCmd -c "import sys; print(sys.version_info.minor)" 2>$null
            if ([int]$pyMajor -ge 3 -and [int]$pyMinor -ge 10) {
                $HeadroomPython = $pyCmd
                break
            }
        }
        catch { continue }
    }
}

if (-not $HeadroomPython) {
    Write-Host "FATAL: Python 3.10+ is required for headroom-ai."
    Write-Host "  Install from https://python.org or via: winget install Python.Python.3.13"
    exit 1
}

$hasHeadroom = Get-Command "headroom" -ErrorAction SilentlyContinue
$HeadroomBin = $null

if ($hasHeadroom) {
    $headroomVer = & headroom --version 2>$null
    Write-Info "headroom: already installed ($headroomVer)"
    $HeadroomBin = (Get-Command "headroom").Source
}
else {
    # --break-system-packages is Linux/macOS only; use --user on Windows
    & $HeadroomPython -m pip install --user "headroom-ai[all]"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARN: headroom installation failed (non-fatal)."
        Write-Host "  Install manually: pip install --user headroom-ai[all]"
    }
    Write-Info "headroom: installed"

    # Locate binary: on Windows user installs land in %APPDATA%\Python\PythonXY\Scripts
    $headroomCmd = Get-Command "headroom" -ErrorAction SilentlyContinue
    if ($headroomCmd) {
        $HeadroomBin = $headroomCmd.Source
    }
    else {
        try {
            $userBase = & $HeadroomPython -m site --user-base 2>$null
            $candidate = Join-Path $userBase "Scripts\headroom.exe"
            if (Test-Path $candidate) { $HeadroomBin = $candidate }
        }
        catch { <# ignore #> }
    }
}

if (-not $HeadroomBin) {
    Write-Info "WARNING: headroom binary not found on PATH after installation."
    Write-Info "  Add Python's Scripts directory to PATH, then re-run setup.ps1."
}

if ($HasClaude -and $HeadroomBin) {
    $mcpListHr = & claude mcp list 2>&1
    if ($mcpListHr -match "headroom") {
        Write-Info "headroom: already registered with Claude Code"
    }
    else {
        & claude mcp add --scope user headroom -- $HeadroomBin mcp serve 2>$null
        Write-Info "headroom: registered with Claude Code"
    }
}

if ($HasCodex -and $HeadroomBin) {
    & codex mcp add headroom -- $HeadroomBin mcp serve 2>$null
    Write-Info "headroom: registered with Codex"
}

# ---------------------------------------------------------------------------
# Output Directory
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "Creating output directory..."
New-Item -ItemType Directory -Path (Join-Path $env:USERPROFILE ".agentic-workflow") -Force | Out-Null
Write-Info "~/.agentic-workflow/: created"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "=== Setup Complete ==="
Write-Host ""
Write-Host "Skills installed (34):"
Write-Host "  Review pipeline:  review, postReview, addressReview"
Write-Host "  Investigation:    rootCause"
Write-Host "  QA:               bugHunt, bugReport"
Write-Host "  Release:          shipRelease, syncDocs"
Write-Host "  Retrospective:    weeklyRetro"
Write-Host "  Planning:         officeHours, productReview, archReview"
Write-Host "  Design:           design-analyze [web|ios], design-language, design-evolve [web|ios],"
Write-Host "                    design-mockup [web|ios], design-implement [web|ios],"
Write-Host "                    design-refine, design-verify [web|ios]"
Write-Host "  Verification:     verify-app, verify-web, verify-ios"
Write-Host "  Utilities:        enhancePrompt, bootstrap"
Write-Host ""
Write-Host "Config location:    $ClaudeDir\"
Write-Host "Statusline:         $ClaudeDir\statusline.sh  (requires bash/WSL)"
Write-Host "Output directory:   ~\.agentic-workflow\<repo-slug>\"
Write-Host "Rules directory:    .claude\rules\ (auto-loaded by Claude Code)"
Write-Host "MCP bridge:         $BridgeDir\"
Write-Host "MCP registered:     Claude Code + Codex (agentic-bridge)"
Write-Host "Plugins:            github, superpowers, compound-engineering, playwright"
Write-Host "UI dashboard:       $UiDir\ (npm run dev -> :3000)"
Write-Host ""
Write-Host "Windows notes:"
Write-Host "  - Skills are installed as directory junctions (equivalent to symlinks)."
Write-Host "  - Hook scripts (.sh) require bash in PATH (Git Bash or WSL) to execute."
Write-Host "  - statusline.sh and shell-integration.sh are bash scripts; they work in WSL/Git Bash."
Write-Host "  - Serena is registered via serena-docker.ps1 (PowerShell Docker wrapper)."
Write-Host "  - XcodeBuildMCP and Swift Serena image are macOS-only and were skipped."
