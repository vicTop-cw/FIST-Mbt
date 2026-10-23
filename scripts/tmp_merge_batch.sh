#!/bin/bash
set -e

cd /e/IDEProjects/AI/FIST-Mbt

branches=(
  "gitcode/slave/fix/memory-log-dup-r133"
  "gitcode/slave/docs/readme-env-bold-r127"
  "gitcode/fix/rhop-native-fixture"
  "gitcode/feat/merge-loss-detector"
  "gitcode/slave/feat/merge-loss-detector"
  "gitcode/fix/display-rank-boundary"
  "gitcode/slave/fix/memory-log-dedupe-r133"
)

for b in "${branches[@]}"; do
  n="${b##*/}"
  echo "=== merge $n ==="
  if git merge --no-edit "$b" 2>&1; then
    echo "  auto"
  else
    echo "  conflict -> ours + MEM FIX"
    mem_files=()
    while IFS= read -r cf; do
      if [[ "$cf" == memory/*.md ]]; then
        mem_files+=("$cf")
      fi
    done < <(git diff --name-only --diff-filter=U 2>/dev/null | grep '\.md$' || true)
    git checkout --ours . 2>&1 | tail -1
    for mf in "${mem_files[@]}"; do
      echo "" >> "$mf"
      echo "--- MERGE-INCOMING ---" >> "$mf"
      git show ":3:$mf" >> "$mf" 2>/dev/null || true
    done
    git add -A
    git commit -m "Merge ${n}: manual" 2>&1 | tail -1
  fi
  echo "  moon check..."
  moon check --target js 2>&1 | tail -1
done

echo "=== push ==="
git push gitcode HEAD:main HEAD:master 2>&1 | tail -2
