$branches = @(
  "gitcode/slave/fix/memory-log-dup-r133",
  "gitcode/slave/docs/readme-env-bold-r127",
  "gitcode/fix/rhop-native-fixture",
  "gitcode/feat/merge-loss-detector",
  "gitcode/slave/feat/merge-loss-detector",
  "gitcode/fix/display-rank-boundary",
  "gitcode/slave/fix/memory-log-dedupe-r133"
)

foreach ($b in $branches) {
  $n = ($b -split '/')[-1]
  Write-Host "=== merge $n ==="
  git merge --no-edit $b 2>&1 | Select-Object -Last 1
  if ($LASTEXITCODE -eq 0) {
    Write-Host "  auto"
  } else {
    Write-Host "  conflict -> ours + MEM FIX"
    $memFiles = @()
    $conflicts = (git diff --name-only --diff-filter=U 2>$null | ? {$_ -match '\.md' })
    foreach ($cf in $conflicts) { if ($cf -match '^memory/') { $memFiles += $cf } }
    git checkout --ours . 2>&1 | Select-Object -Last 1
    foreach ($mf in $memFiles) {
      $theirs = git show ":3:$mf" 2>&1
      Add-Content -Path "$mf" -Value "`n--- MERGE-INCOMING ---`n"
      Add-Content -Path "$mf" -Value $theirs
    }
    git add -A
    $msg = "Merge ${n}: manual"
    git commit -m $msg 2>&1 | Select-Object -Last 1
  }
  Write-Host "  moon check..."
  moon check --target js 2>&1 | Select-Object -Last 1
}
