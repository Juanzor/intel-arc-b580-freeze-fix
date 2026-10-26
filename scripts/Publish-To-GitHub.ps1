# ==============================================================================
# Publish-To-GitHub.ps1
# Authenticates with GitHub CLI (if needed), creates the public repository
# 'intel-arc-b580-freeze-fix' with SEO/AI topics, and pushes the main branch.
# ==============================================================================
$ErrorActionPreference = "Continue"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host "Checking GitHub CLI (gh) authentication..." -ForegroundColor Cyan
gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Initiating GitHub browser login (press Enter when prompted to open github.com)..." -ForegroundColor Yellow
    gh auth login --hostname github.com --git-protocol https --web
}

$RepoName = "intel-arc-b580-freeze-fix"
$Description = "Forensic root-cause analysis & permanent automated fix for Intel Arc B580 / Battlemage startup freeze, Code 43 (Event ID 1011), and DDU Safe Mode loop on Windows 11."

Write-Host "Creating public repository '$RepoName' on GitHub and pushing commits..." -ForegroundColor Cyan
gh repo create $RepoName --public --description $Description --source "." --remote "origin" --push

Write-Host "Adding SEO & AI discovery topics to repository..." -ForegroundColor Cyan
gh repo edit --add-topic "intel-arc,intel-arc-b580,battlemage,code-43,event-id-1011,windows-11-24h2,ddu,iommu,am5,presentmon,gpu-freeze,troubleshooting"

$repoUrl = gh repo view --json url -q ".url"
Write-Host "`n==================================================================" -ForegroundColor Green
Write-Host "  REPOSITORY PUBLISHED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "  URL: $repoUrl" -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green
Start-Process $repoUrl
