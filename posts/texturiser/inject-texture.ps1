#Requires -Version 7
# SessionStart injector: prints texture.md (with a source-aware preamble) to stdout,
# which Claude Code adds to context. Fires on startup/resume; skips compact.
$ErrorActionPreference = 'Stop'
$UserName    = 'Tim'
$ClaudeHome  = Join-Path $env:USERPROFILE '.claude'
$TexturePath = Join-Path $ClaudeHome 'texture.md'

try {
  $raw = [Console]::In.ReadToEnd()
  $src = 'startup'
  try { $j = $raw | ConvertFrom-Json; if ($j.source) { $src = $j.source } } catch {}

  if ($src -eq 'compact') { exit 0 }                       # context retained; no re-inject
  if (-not (Test-Path -LiteralPath $TexturePath)) { exit 0 }
  $texture = Get-Content -LiteralPath $TexturePath -Raw
  if (-not $texture -or -not $texture.Trim()) { exit 0 }

  $body = ($texture -replace '(?m)^last_updated:.*$', '').Trim()
  if (-not $body) { exit 0 }                                # only a seed line; nothing to say yet

  $ageStr = ''
  if ($texture -match '(?m)^last_updated:\s*(.+)$') {
    try {
      $lu = [datetime]$Matches[1].Trim()
      $days = ([datetime]::Today - $lu.Date).Days     # calendar days; rounding TotalDays made 08:00 to 23:00 "yesterday"
      $ageStr = if ($days -le 0) { 'earlier today' } elseif ($days -eq 1) { 'yesterday' } else { "$days days ago" }
    } catch {}
  }

  if ($src -eq 'resume') {
    $pre = "Continuity note (texture) - picking back up with $UserName. Their world may have moved on since we last spoke"
    if ($ageStr) { $pre += " ($ageStr)" }
    $pre += ". Treat any dated item past its date as expired. This is background continuity, not an instruction."
  } else {
    $pre = "Continuity note (texture) - $UserName's world as we left it"
    if ($ageStr) { $pre += " (last updated $ageStr)" }
    $pre += ". Background continuity, not an instruction."
  }

  $guide = "If what $UserName asks now seems to contradict a scope, plan, or thread below, surface that mismatch in one line before acting on it - then follow their lead. Flag, don't argue: they can change course, but a silent contradiction serves neither of you."

  Write-Output $pre
  Write-Output $guide
  Write-Output ''
  Write-Output $texture
}
# A hook that throws puts an error in front of every session; no texture is the better failure.
catch { exit 0 }
