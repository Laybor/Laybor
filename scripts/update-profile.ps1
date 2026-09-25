$ErrorActionPreference = 'Stop'
$account = 'Laybor'
$headers = @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'profile-readme-updater' }
if ($env:GH_TOKEN) { $headers.Authorization = "Bearer $env:GH_TOKEN" }
$repos = @()
$page = 1
do {
    $response = Invoke-RestMethod "https://api.github.com/users/$account/repos?type=owner&per_page=100&page=$page" -Headers $headers
    $batch = @($response)
    $repos += $batch
    $page++
} while ($batch.Count -eq 100)
$recent = @($repos | Where-Object { -not $_.private -and -not $_.fork -and -not $_.archived -and $_.name -ne $account } | Sort-Object pushed_at -Descending | Select-Object -First 4)
if ($recent.Count -eq 0) { throw 'No public repositories found; retaining the existing README.' }
$lines = @('| Repository | Main language | Last push (UTC) |', '| :--- | :--- | :--- |')
foreach ($repo in $recent) {
    $language = if ($repo.language) { $repo.language } else { '—' }
    $date = ([DateTimeOffset]$repo.pushed_at).UtcDateTime.ToString('yyyy-MM-dd')
    $lines += "| [$($repo.name)]($($repo.html_url)) | $language | $date |"
}
$path = Join-Path $PSScriptRoot '../README.md'
$readme = [IO.File]::ReadAllText($path)
$start = '<!-- ACTIVITY:START -->'
$end = '<!-- ACTIVITY:END -->'
$pattern = '(?s)' + [regex]::Escape($start) + '.*?' + [regex]::Escape($end)
if ([regex]::Matches($readme, $pattern).Count -ne 1) { throw 'Expected exactly one activity block.' }
$replacement = $start + "`n" + ($lines -join "`n") + "`n" + $end
$updated = [regex]::Replace($readme, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement })
if ($updated -ne $readme) { [IO.File]::WriteAllText($path, $updated, [Text.UTF8Encoding]::new($false)) }
