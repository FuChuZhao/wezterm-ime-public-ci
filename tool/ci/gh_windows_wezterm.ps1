param(
  [Parameter(Mandatory = $true)]
  [string]$Repo,

  [string]$Workflow = "build-windows.yml",

  [string]$Ref = "main",

  [string]$SourceRef = "main",

  [switch]$DownloadArtifact,

  [switch]$DeleteArtifactsAfterDownload,

  [string]$OutDir = "C:\codex-temp\ci-artifacts",

  [int]$PollSeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-LatestRunId {
  param(
    [string]$Repo,
    [string]$Workflow
  )
  $json = gh run list -R $Repo --workflow $Workflow -L 1 --json databaseId,status,conclusion | ConvertFrom-Json
  if (-not $json -or -not $json[0].databaseId) {
    throw "无法获取 workflow run id（Repo=$Repo Workflow=$Workflow）"
  }
  return [int64]$json[0].databaseId
}

function Wait-Run {
  param(
    [string]$Repo,
    [int64]$RunId,
    [int]$PollSeconds
  )
  while ($true) {
    $run = gh run view $RunId -R $Repo --json status,conclusion,updatedAt | ConvertFrom-Json
    if ($run.status -eq "completed") {
      if ($run.conclusion -ne "success") {
        throw "CI 失败：run=$RunId conclusion=$($run.conclusion)"
      }
      return
    }
    Start-Sleep -Seconds $PollSeconds
  }
}

function Delete-RunArtifacts {
  param(
    [string]$Repo,
    [int64]$RunId
  )
  $arts = gh api "/repos/$Repo/actions/runs/$RunId/artifacts" | ConvertFrom-Json
  foreach ($a in $arts.artifacts) {
    if ($a.id) {
      gh api -X DELETE "/repos/$Repo/actions/artifacts/$($a.id)" | Out-Null
    }
  }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

gh workflow run $Workflow -R $Repo --ref $Ref -f source_ref=$SourceRef | Out-Null
$runId = Get-LatestRunId -Repo $Repo -Workflow $Workflow
Write-Host "run_id=$runId"

Wait-Run -Repo $Repo -RunId $runId -PollSeconds $PollSeconds

if ($DownloadArtifact) {
  $dest = Join-Path $OutDir $runId
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  gh run download $runId -R $Repo -D $dest | Out-Null
  Write-Host "download_dir=$dest"
}

if ($DeleteArtifactsAfterDownload) {
  Delete-RunArtifacts -Repo $Repo -RunId $runId
  Write-Host "artifacts_deleted=1"
}

