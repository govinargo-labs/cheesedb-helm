#!/usr/bin/env bash
# Moves the chart to a new cheesedb release, the way README.md says:
# a new cheesedb release bumps the chart's minor number (0.2.0 -> 0.3.0).
#
#   .github/scripts/bump-app.sh 0.5.0
#
# Edits, in place:
#   charts/cheesedb/Chart.yaml  appVersion, version
#   README.md                   install commands, the image to verify,
#                               a new row in the version table
# and prints the new chart version. Run from the repository root.
set -euo pipefail

app=${1:?usage: bump-app.sh <cheesedb version, e.g. 0.5.0>}
if ! grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' <<<"$app"; then
  echo "not a cheesedb version: $app" >&2
  exit 1
fi

chart=charts/cheesedb/Chart.yaml
old_app=$(awk -F'"' '/^appVersion:/ {print $2}' "$chart")
old_chart=$(awk '/^version:/ {print $2}' "$chart")
if ! grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' <<<"$old_chart"; then
  echo "cannot read the chart version in $chart: $old_chart" >&2
  exit 1
fi
if [ "$app" = "$old_app" ]; then
  echo "the chart already installs cheesedb $app" >&2
  exit 1
fi
# Never move backwards.
if [ "$(printf '%s\n%s\n' "$old_app" "$app" | sort -V | tail -n1)" != "$app" ]; then
  echo "cheesedb $app is older than $old_app, the chart's appVersion" >&2
  exit 1
fi

IFS=. read -r major minor _ <<<"$old_chart"
new_chart="$major.$((minor + 1)).0"

# perl -pi works the same on Linux and macOS (sed -i does not).
APP=$app OLD_APP=$old_app NEW_CHART=$new_chart OLD_CHART=$old_chart perl -pi -e '
  s/^appVersion: .*/appVersion: "$ENV{APP}"/;
  s/^version: .*/version: $ENV{NEW_CHART}/;
' "$chart"

# README: the install commands, the image in the cosign example, and a new
# first row in the version table ("| 0.3.x | 0.5.0 |").
NEW_ROW="| ${new_chart%.0}.x | $app |" APP=$app OLD_APP=$old_app \
NEW_CHART=$new_chart OLD_CHART=$old_chart perl -pi -e '
  s/--version \Q$ENV{OLD_CHART}\E\b/--version $ENV{NEW_CHART}/g;
  s/cheesedb:\Q$ENV{OLD_APP}\E\b/cheesedb:$ENV{APP}/g;
  if (!$done && $prev =~ /^\| Chart version \|/ && /^\|---\|---\|$/) {
    $_ .= "$ENV{NEW_ROW}\n";
    $done = 1;
  }
  $prev = $_;
' README.md

# Fail if any edit did not land, rather than open a half-done pull request.
grep -qx "appVersion: \"$app\"" "$chart"
grep -qx "version: $new_chart" "$chart"
grep -qF -- "--version $new_chart" README.md
grep -qF "cheesedb:$app " README.md
grep -qxF "| ${new_chart%.0}.x | $app |" README.md

echo "$new_chart"
