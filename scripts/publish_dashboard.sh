#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 /path/to/hpc/project [project-name]" >&2
  exit 2
fi

project_dir=$1
project_name=${2:-}
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$repo_dir/dashboard-data"

if [[ -n "$project_name" ]]; then
  python3 "$repo_dir/scripts/build_dashboard_bundle.py" "$project_dir" --output "$output_dir" --name "$project_name"
else
  python3 "$repo_dir/scripts/build_dashboard_bundle.py" "$project_dir" --output "$output_dir"
fi

echo
echo "Review the generated files, then publish them with:"
echo "  cd $repo_dir"
echo "  git add dashboard-data"
echo "  git commit -m 'Update dashboard data'"
echo "  git push"
