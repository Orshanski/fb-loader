#!/usr/bin/env bash
# Run the test suite with code coverage and emit a Sonar-compatible
# Generic Test Coverage XML report.
#
# Output:
#   build/DerivedData/             — Xcode build artefacts (gitignored)
#   build/coverage.xml             — Sonar Generic Test Coverage XML
#
# Coverage is collected for the production target only (FB Loader.app);
# test targets are filtered out before the report is emitted.
#
# Usage: ./scripts/coverage.sh [extra xcodebuild args…]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DERIVED="$REPO_ROOT/build/DerivedData"
COVERAGE_XML="$REPO_ROOT/build/coverage.xml"
mkdir -p "$REPO_ROOT/build"

# Wipe DerivedData so the resulting .xcresult is a single fresh bundle
# (avoids picking up an old timestamped one in the find below).
rm -rf "$DERIVED"

# Project lives in ~/Documents (iCloud Drive). iCloud continuously stamps
# files with com.apple.fileprovider/com.apple.FinderInfo extended
# attributes, which breaks `codesign` on the .xctest test bundle with
# "resource fork, Finder information, or similar detritus not allowed".
# A pre-build `xattr -cr` doesn't help — iCloud restamps faster than
# xcodebuild reaches the codesign step. Fix: skip codesign for the test
# build (CODE_SIGNING_ALLOWED=NO). Local test execution doesn't need a
# signed bundle on macOS — the runner trusts the development host.
echo "==> Running tests with code coverage…"
xcodebuild \
  -project "FB Loader/FB Loader.xcodeproj" \
  -scheme "FB Loader" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED" \
  -enableCodeCoverage YES \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test "$@"

XCRESULT=$(find "$DERIVED" -type d -name "*.xcresult" -print | head -1)
if [[ -z "$XCRESULT" ]]; then
  echo "ERROR: no .xcresult bundle found under $DERIVED" >&2
  exit 1
fi

echo "==> Converting coverage to Sonar XML…"
python3 "$(dirname "${BASH_SOURCE[0]}")/xccov-to-sonar.py" \
  "$XCRESULT" "$REPO_ROOT" > "$COVERAGE_XML"

LINES=$(grep -c "<lineToCover" "$COVERAGE_XML" || true)
FILES=$(grep -c "<file " "$COVERAGE_XML" || true)
echo "==> Done. $FILES files, $LINES lines tracked → $COVERAGE_XML"
