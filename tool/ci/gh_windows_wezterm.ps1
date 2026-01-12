param(
  [Parameter(Mandatory = $true)]
  [string]$Repo,

  [string]$Workflow = "build-windows.yml",

  [string]$Ref = "main",

  [string]$SourceRef = "main",

  [Nullable[Int64]]$RunId,

  [switch]$DownloadArtifact,

  [switch]$DeleteArtifactsAfterDownload,

  [string]$OutDir = "C:\codex-temp\ci-artifacts",

  [int]$PollSeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-GhWithRetry {
  param(
    [Parameter(Mandatory = $true)]
    [scriptblock]$Block,

    [int]$MaxAttempts = 30,

    [int]$SleepSeconds = 5
  )

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
      $result = & $Block
      if ($LASTEXITCODE -eq 0) {
        return $result
      }
    } catch {
      # Fall through to retry
    }

    if ($attempt -lt $MaxAttempts) {
      Start-Sleep -Seconds $SleepSeconds
    }
  }

  throw "gh 调用多次失败（MaxAttempts=$MaxAttempts）"
}

function Get-LatestRunId {
  param(
    [string]$Repo,
    [string]$Workflow
  )
  $raw = Invoke-GhWithRetry { gh run list -R $Repo --workflow $Workflow -L 1 --json databaseId,status,conclusion }
  $json = $raw | ConvertFrom-Json
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
    $raw = $null
    try {
      $raw = gh run view $RunId -R $Repo --json status,conclusion,updatedAt
    } catch {
      $raw = $null
    }

    if ($LASTEXITCODE -ne 0 -or -not $raw) {
      Start-Sleep -Seconds $PollSeconds
      continue
    }

    $run = $null
    try {
      $run = $raw | ConvertFrom-Json
    } catch {
      $run = $null
    }

    if (-not $run -or -not $run.status) {
      Start-Sleep -Seconds $PollSeconds
      continue
    }

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
  $raw = Invoke-GhWithRetry { gh api "/repos/$Repo/actions/runs/$RunId/artifacts" }
  $arts = $raw | ConvertFrom-Json
  foreach ($a in $arts.artifacts) {
    if ($a.id) {
      Invoke-GhWithRetry { gh api -X DELETE "/repos/$Repo/actions/artifacts/$($a.id)" | Out-Null }
    }
  }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if ($RunId) {
  $runId = [int64]$RunId
} else {
  Invoke-GhWithRetry { gh workflow run $Workflow -R $Repo --ref $Ref -f source_ref=$SourceRef | Out-Null }
  $runId = Get-LatestRunId -Repo $Repo -Workflow $Workflow
}
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
