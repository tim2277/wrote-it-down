#Requires -Version 7
# SessionEnd worker: folds the conversation delta into ~/.claude/texture.md.
# Stage 1 (no -PayloadFile): invoked by the hook. Captures stdin, detaches, returns fast.
# Stage 2 (-PayloadFile):    the detached worker that does the real folding.
param([string]$PayloadFile)

$ErrorActionPreference = 'Stop'
$UserName      = 'Tim'     # texture-prompt.md uses the same names for its TIM:/OPUS: labels
$AssistantName = 'Opus'
$ClaudeHome    = Join-Path $env:USERPROFILE '.claude'
$TexturePath   = Join-Path $ClaudeHome 'texture.md'
$MarkersPath   = Join-Path $ClaudeHome 'texture-markers.json'
$PromptPath    = Join-Path $ClaudeHome 'texture-prompt.md'
$NoHooksPath   = Join-Path $ClaudeHome 'texturise-nohooks.settings.json'
$LogPath       = Join-Path $ClaudeHome 'texturise.log'
$HistoryDir    = Join-Path $ClaudeHome 'texture-history'
$KeepHistory   = 30
$Model         = 'sonnet'    # the alias, so it tracks the latest Sonnet instead of going stale
$MaxDeltaChars = 1000000     # ~400k tokens at 2.5 chars/token, well inside the 1M window. A backstop, not a budget:
                             # an oversized fold would fail, never advance its marker, and fail again every session end
$DryRun        = [bool]$env:TEXTURISE_DRYRUN

function Log($m) {
  if ($DryRun) { Write-Output $m; return }   # a dry run writes nothing, but still shows what a real run would log
  try { Add-Content -LiteralPath $LogPath -Value ("{0}  {1}" -f (Get-Date).ToString('o'), $m) -Encoding UTF8 } catch {}
}

# --- Stage 1: foreground hook invocation - capture stdin, spawn detached worker, exit ---
# SessionEnd hooks get seconds and a fold takes minutes, so the hook only hands off.
if (-not $PayloadFile) {
  if ($env:CLAUDE_TEXTURISE_ACTIVE) { exit 0 }   # recursion guard: we're inside a fold's own claude -p
  $raw = [Console]::In.ReadToEnd()
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("texturise-" + [guid]::NewGuid().ToString('N') + ".json")
  Set-Content -LiteralPath $tmp -Value $raw -Encoding UTF8
  Start-Process -FilePath 'pwsh' -WindowStyle Hidden -ArgumentList @(
    '-NoProfile','-NonInteractive','-File', $PSCommandPath, '-PayloadFile', $tmp
  ) | Out-Null
  exit 0
}

# --- Stage 2: detached worker ---
# Two sessions ending together would each fold against the same texture.md and the
# last writer would win, while both markers advanced - the loser's delta gone for good.
# Hold the lock from reading markers to writing them so folds run one after another.
$lock = [System.Threading.Mutex]::new($false, 'Local\claude-texturise')
$held = $false
try {
  if (-not (Test-Path -LiteralPath $PayloadFile)) { exit 0 }
  $payload = Get-Content -LiteralPath $PayloadFile -Raw | ConvertFrom-Json
  if (-not $DryRun) { Remove-Item -LiteralPath $PayloadFile -Force -ErrorAction SilentlyContinue }

  try { $held = $lock.WaitOne([TimeSpan]::FromMinutes(10)) }
  catch [System.Threading.AbandonedMutexException] { $held = $true }   # previous holder died; state on disk is still consistent
  if (-not $held) { Log "abort: timed out waiting for another fold"; exit 0 }

  $sessionId  = $payload.session_id
  $transcript = $payload.transcript_path
  $cwd        = $payload.cwd
  if (-not $sessionId -or -not $transcript -or -not (Test-Path -LiteralPath $transcript)) {
    Log "skip: missing session/transcript"; exit 0
  }
  $repo = if ($cwd) { Split-Path $cwd -Leaf } else { 'unknown' }

  # Markers are per session, so interleaved sessions never skip each other's messages
  $markers = @{}
  if (Test-Path -LiteralPath $MarkersPath) {
    try { (Get-Content -LiteralPath $MarkersPath -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $markers[$_.Name] = $_.Value } } catch {}
  }
  $lastFolded = [datetime]::MinValue
  if ($markers.ContainsKey($sessionId)) {
    try { $lastFolded = ([datetime]$markers[$sessionId]).ToUniversalTime() } catch {}
  }

  $userTurns = 0
  $parts = New-Object System.Collections.Generic.List[string]
  $maxTs = $lastFolded
  foreach ($line in [System.IO.File]::ReadLines($transcript)) {
    if (-not $line) { continue }
    try { $o = $line | ConvertFrom-Json } catch { continue }
    if ($o.type -ne 'user' -and $o.type -ne 'assistant') { continue }
    if ($o.isSidechain) { continue }
    if (-not $o.timestamp) { continue }
    $ts = ([datetime]$o.timestamp).ToUniversalTime()
    if ($ts -le $lastFolded) { continue }
    if ($ts -gt $maxTs) { $maxTs = $ts }

    if ($o.type -eq 'user') {
      if ($o.isMeta) { continue }                      # injected by hooks, not typed
      if ($o.message.content -is [string]) {           # a typed prompt; tool results arrive as arrays
        if ($o.message.content -match '\A\s*<task-notification>') { continue }   # background agents reporting in, not typed
        $userTurns++
        $parts.Add("$($UserName.ToUpper()): " + $o.message.content)
      }
    } else {
      $txt = ($o.message.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n"
      if ($txt) { $parts.Add("$($AssistantName.ToUpper()): " + $txt) }
    }
  }

  if ($userTurns -eq 0) { Log "early-exit: 0 user turns ($repo)"; exit 0 }

  $delta = ($parts -join "`n`n")
  if ($delta.Length -gt $MaxDeltaChars) {
    # The marker still advances past the dropped head, so say so rather than lose it quietly
    Log "truncated: kept last $MaxDeltaChars of $($delta.Length) chars ($repo)"
    $delta = $delta.Substring($delta.Length - $MaxDeltaChars)
  }

  $currentTexture = if (Test-Path -LiteralPath $TexturePath) { Get-Content -LiteralPath $TexturePath -Raw } else { '' }
  if (-not $currentTexture -or -not $currentTexture.Trim()) { $currentTexture = '(empty - first run)' }
  $lastUpdatedStr = 'never'
  if ($currentTexture -match '(?m)^last_updated:\s*(.+)$') { $lastUpdatedStr = $Matches[1].Trim() }
  $now = (Get-Date).ToString('dddd, dd MMMM yyyy, HH:mm')

  $template = (Get-Content -LiteralPath $PromptPath -Raw).
                Replace('{{DATETIME}}', $now).
                Replace('{{LAST_UPDATED}}', $lastUpdatedStr).
                Replace('{{REPO}}', $repo)
  $composed = $template +
    "`n`n=== CURRENT TEXTURE (below) ===`n" + $currentTexture +
    "`n`n=== TRANSCRIPT DELTA (conversation since last fold) ===`n" + $delta

  if ($DryRun) {
    Write-Output "DRYRUN userTurns=$userTurns deltaChars=$($delta.Length) repo=$repo lastFolded=$($lastFolded.ToString('o')) maxTs=$($maxTs.ToString('o'))"
    Write-Output "----- composed prompt tail -----"
    Write-Output ($composed.Substring([Math]::Max(0, $composed.Length - 1200)))
    exit 0
  }

  # The fold is a Claude Code session too: without both guards its own SessionEnd would fold it
  # It is also an agent. Left with tools in the repo's cwd, it "maintained texture.md" by writing one
  # into that repo's memory dir and replying with a summary. No tools, neutral cwd: stdout is the only way out.
  $env:CLAUDE_TEXTURISE_ACTIVE = '1'
  Push-Location ([System.IO.Path]::GetTempPath())
  try { $out = $composed | claude -p --model $Model --settings $NoHooksPath --tools '' --strict-mcp-config --no-session-persistence 2>$null }
  finally { Pop-Location; $env:CLAUDE_TEXTURISE_ACTIVE = $null }

  $outStr = (($out -join "`n")).Trim()
  if (-not $outStr) { Log "abort: empty claude output ($repo)"; exit 0 }
  # Anchored: a chatty preamble or code fence must not get injected into every session
  if ($outStr -notmatch '\Alast_updated:') {
    $head = $outStr.Substring(0, [Math]::Min(120, $outStr.Length)) -replace '\s+', ' '
    Log "abort: output doesn't start with last_updated ($repo): $head"; exit 0
  }

  # The prompt tells the model that cuts are recoverable; this is what makes that true
  if (Test-Path -LiteralPath $TexturePath) {
    New-Item -ItemType Directory -Force -Path $HistoryDir | Out-Null
    Copy-Item -LiteralPath $TexturePath -Destination (Join-Path $HistoryDir ("texture-{0}.md" -f (Get-Date -Format 'yyyyMMdd-HHmmss')))
    Get-ChildItem -LiteralPath $HistoryDir -Filter 'texture-*.md' | Sort-Object Name -Descending |
      Select-Object -Skip $KeepHistory | Remove-Item -Force
  }

  # Write then move, so a session starting mid-fold never reads a half-written texture
  $tmpOut = $TexturePath + '.tmp'
  Set-Content -LiteralPath $tmpOut -Value $outStr -Encoding UTF8
  Move-Item -LiteralPath $tmpOut -Destination $TexturePath -Force

  # Advance the marker only after a successful write, so a failed fold is retried, not lost
  $markers[$sessionId] = $maxTs.ToString('o')
  ($markers | ConvertTo-Json) | Set-Content -LiteralPath $MarkersPath -Encoding UTF8

  Log "folded: $userTurns user turns, delta=$($delta.Length) chars ($repo)"
}
catch {
  Log "error: $($_.Exception.Message)"
}
finally {
  if ($held) { $lock.ReleaseMutex() }
  $lock.Dispose()
}
