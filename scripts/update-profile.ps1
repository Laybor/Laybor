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

# Generate first-party cards so the profile does not rely on a public stats server.
$profile = Invoke-RestMethod "https://api.github.com/users/$account" -Headers $headers
$projects = @($repos | Where-Object { -not $_.private -and -not $_.fork -and $_.name -ne $account })
$stars = ($projects | Measure-Object stargazers_count -Sum).Sum
$forks = ($projects | Measure-Object forks_count -Sum).Sum
$stats = @"
<svg xmlns="http://www.w3.org/2000/svg" width="960" height="230" viewBox="0 0 960 230" role="img" aria-labelledby="title desc">
<title id="title">Laybor public project statistics</title>
<desc id="desc">$($projects.Count) original public projects, $stars stars, $($profile.followers) followers, $forks forks received. Profile repository excluded from project metrics.</desc>
<rect width="960" height="230" rx="18" fill="#282a36"/>
<g font-family="Segoe UI, Arial, sans-serif">
<text x="32" y="40" fill="#bd93f9" font-size="15" letter-spacing="3">THE WORKSHOP / BY THE NUMBERS</text>
<path d="M256 72V166M480 72V166M704 72V166" stroke="#44475a"/>
<g font-size="48" font-weight="700"><text x="32" y="123" fill="#bd93f9">$($projects.Count)</text><text x="288" y="123" fill="#ff79c6">$stars</text><text x="512" y="123" fill="#8be9fd">$($profile.followers)</text><text x="736" y="123" fill="#50fa7b">$forks</text></g>
<g fill="#f8f8f2" font-size="17"><text x="32" y="156">Public projects</text><text x="288" y="156">Stars earned</text><text x="512" y="156">Followers</text><text x="736" y="156">Forks received</text></g>
<text x="32" y="205" fill="#b8b6c8" font-size="13">Public originals only · Profile repository excluded · Small beginnings, real progress.</text>
</g></svg>
"@
$totals = @{}
foreach ($repo in $projects) {
    $languages = Invoke-RestMethod $repo.languages_url -Headers $headers
    foreach ($property in $languages.PSObject.Properties) {
        $totals[$property.Name] = [long]$totals[$property.Name] + [long]$property.Value
    }
}
$sum = ($totals.Values | Measure-Object -Sum).Sum
$rows = @($totals.GetEnumerator() | Sort-Object Value -Descending)
$height = 108 + 54 * [Math]::Max(1, $rows.Count)
$elements = @()
$colors = @('#bd93f9', '#ff79c6', '#8be9fd', '#50fa7b', '#f1fa8c')
$index = 0
foreach ($row in $rows) {
    $y = 78 + 54 * $index
    $label = [Security.SecurityElement]::Escape($row.Key)
    $ratio = $row.Value / $sum
    $pct = ($ratio * 100).ToString('0.0', [Globalization.CultureInfo]::InvariantCulture)
    $width = [Math]::Round(620 * $ratio)
    $color = $colors[$index % $colors.Count]
    $elements += "<text x='32' y='$y' fill='#f8f8f2' font-size='16'>$label</text><rect x='210' y='$($y - 15)' width='620' height='18' rx='9' fill='#44475a'/><rect x='210' y='$($y - 15)' width='$width' height='18' rx='9' fill='$color'/><text x='850' y='$y' fill='$color' font-size='16'>$pct%</text>"
    $index++
}
if ($rows.Count -eq 0) { $elements += "<text x='32' y='78' fill='#f8f8f2'>Language data will appear as projects grow.</text>" }
$languageSvg = "<svg xmlns='http://www.w3.org/2000/svg' width='960' height='$height' viewBox='0 0 960 $height' role='img' aria-labelledby='title'><title id='title'>Languages by code bytes in original public projects; not proficiency</title><rect width='960' height='$height' rx='18' fill='#282a36'/><g font-family='Segoe UI, Arial, sans-serif'><text x='32' y='38' fill='#8be9fd' font-size='15' letter-spacing='3'>WHAT THE CODE IS MADE OF</text>$($elements -join '')<text x='32' y='$($height - 22)' fill='#b8b6c8' font-size='13'>Share of code bytes across public originals · Language usage, not a skill rating.</text></g></svg>"
$assets = Join-Path $PSScriptRoot '../assets'
[IO.File]::WriteAllText((Join-Path $assets 'stats.svg'), $stats, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $assets 'languages.svg'), $languageSvg, [Text.UTF8Encoding]::new($false))
