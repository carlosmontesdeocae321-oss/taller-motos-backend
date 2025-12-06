<#
PowerShell helper to push this repo to a GitHub remote safely.
It will NOT overwrite your existing 'origin' remote.
Usage:
  .\push_to_github.ps1 -remoteUrl "https://github.com/USER/REPO.git"
#>
param(
  [string]$remoteUrl = "https://github.com/carlosmontesdeocae321-oss/taller-motos-backend.git",
  [string]$remoteName = "taller-motos-remote",
  [string]$branch = "main"
)

Set-StrictMode -Version Latest

function Run-Git([string[]]$args) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "git"
  $psi.Arguments = $args -join ' '
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $proc = [System.Diagnostics.Process]::Start($psi)
  $stdout = $proc.StandardOutput.ReadToEnd()
  $stderr = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()
  return @{ExitCode = $proc.ExitCode; StdOut = $stdout; StdErr = $stderr}
}

Write-Host "Target remote: $remoteUrl (remote name: $remoteName)" -ForegroundColor Cyan

# Ensure we're in a git repo
$inRepo = (Run-Git @('rev-parse','--is-inside-work-tree')).ExitCode -eq 0
if (-not $inRepo) {
  Write-Host "No git repository detected. Initializing git..." -ForegroundColor Yellow
  Run-Git @('init') | Out-Null
}

# Ensure there is at least one commit
$hasHead = (Run-Git @('rev-parse','--verify','HEAD')).ExitCode -eq 0
if (-not $hasHead) {
  Write-Host "No commits found. Creating an initial commit..." -ForegroundColor Yellow
  Run-Git @('add','.') | Out-Null
  $res = Run-Git @('commit','-m','Initial commit for Taller de Motos backend')
  if ($res.ExitCode -ne 0) {
    Write-Host "Commit failed: $($res.StdErr)" -ForegroundColor Red
    Write-Host "Please create a commit manually and re-run this script." -ForegroundColor Red
    exit 1
  }
}

# Check if any remote already points to the same URL
$remoteMatch = Run-Git @('remote','-v')
if ($remoteMatch.ExitCode -ne 0) { Write-Host "Could not get remotes: $($remoteMatch.StdErr)" -ForegroundColor Red; exit 1 }

$alreadyPointing = $remoteMatch.StdOut -split "\r?\n" | Where-Object { $_ -and $_ -match [regex]::Escape($remoteUrl) }
if ($alreadyPointing) {
  Write-Host "A remote pointing to $remoteUrl already exists:" -ForegroundColor Green
  $alreadyPointing | ForEach-Object { Write-Host "  $_" }
  Write-Host "No remote was added. You can push using the existing remote name shown above." -ForegroundColor Green
} else {
  # Add a new remote under a safe, unique name (do not override 'origin')
  $existingRemotes = (Run-Git @('remote')).StdOut -split "\r?\n" | Where-Object { $_ }
  if ($existingRemotes -contains $remoteName) {
    $answer = Read-Host "Remote '$remoteName' already exists. Overwrite its URL? (y/N)"
    if ($answer -ne 'y') { Write-Host "Aborting to avoid overwriting existing remote. Choose a different remote name." -ForegroundColor Yellow; exit 1 }
    Run-Git @('remote','remove',$remoteName) | Out-Null
  }
  $res = Run-Git @('remote','add',$remoteName,$remoteUrl)
  if ($res.ExitCode -ne 0) { Write-Host "Failed to add remote: $($res.StdErr)" -ForegroundColor Red; exit 1 }
  Write-Host "Added remote '$remoteName' -> $remoteUrl" -ForegroundColor Green
}

# Ensure branch name and push
Run-Git @('branch','-M',$branch) | Out-Null
Write-Host "Pushing branch '$branch' to remote '$remoteName'..." -ForegroundColor Cyan
$pushRes = Run-Git @('push','-u',$remoteName,$branch)
if ($pushRes.ExitCode -ne 0) {
  Write-Host "Push failed." -ForegroundColor Red
  Write-Host $pushRes.StdErr
  Write-Host "If authentication fails, run 'gh auth login' or configure credentials and try again." -ForegroundColor Yellow
  exit $pushRes.ExitCode
}

Write-Host "Push successful. Remote '$remoteName' now has branch '$branch'." -ForegroundColor Green
Write-Host "You can verify with: git remote -v" -ForegroundColor Green
