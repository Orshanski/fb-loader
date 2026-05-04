#!/usr/bin/env python3
"""
Convert per-file Xcode coverage data from a .xcresult bundle into
SonarQube's Generic Test Coverage XML format.

Why this exists: SonarCloud's Swift analyzer doesn't ingest Xcode's
native .xccovreport / .profdata directly; it expects either a
language-specific report or the language-agnostic "Generic Test
Coverage" XML (https://docs.sonarcloud.io/.../generic-test-data/).
This script bridges xcodebuild's coverage output to that format.

Skipped from the report:
- Test targets (per-target name contains "Tests")
- Non-Swift files (.h, .plist, .json from generated assets, …)
- Lines marked "*" by xccov — those are non-executable (declarations,
  comments, blank); Sonar's coverage % shouldn't count them either way.

Usage:
    xccov-to-sonar.py <path-to.xcresult> <repo-root>

Writes XML to stdout.
"""
import json
import subprocess
import sys
from xml.sax.saxutils import escape


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    xcresult, repo_root = sys.argv[1], sys.argv[2]
    if not repo_root.endswith("/"):
        repo_root_prefix = repo_root + "/"
    else:
        repo_root_prefix = repo_root

    # Top-level report: list of targets, each with files (absolute paths).
    report = json.loads(subprocess.check_output([
        "xcrun", "xccov", "view", "--report", "--json", xcresult,
    ]))

    out = ['<?xml version="1.0" encoding="UTF-8"?>', '<coverage version="1">']

    for target in report.get("targets", []):
        name = target.get("name", "")
        # Skip test bundles — they aren't production code.
        if "Tests" in name or "Test" == name:
            continue
        for file_entry in target.get("files", []):
            path = file_entry.get("path", "")
            if not path.endswith(".swift"):
                continue
            rel = path[len(repo_root_prefix):] if path.startswith(repo_root_prefix) else path
            lines = per_file_lines(xcresult, path)
            if not lines:
                continue
            out.append(f'  <file path="{escape(rel)}">')
            for line_num, covered in lines:
                out.append(
                    f'    <lineToCover lineNumber="{line_num}" '
                    f'covered="{"true" if covered else "false"}"/>'
                )
            out.append('  </file>')

    out.append('</coverage>')
    sys.stdout.write("\n".join(out) + "\n")
    return 0


def per_file_lines(xcresult: str, file_path: str):
    """Return [(line_number, covered_bool)] for executable lines.

    `xcrun xccov view --archive --file PATH XCRESULT` prints one line per
    source line in the form "    N: hits<TAB>source...":
        - hits == "*": non-executable, skip
        - hits == "0": executable but not hit → covered=false
        - hits >= 1   : covered=true
    """
    raw = subprocess.check_output([
        "xcrun", "xccov", "view", "--archive", "--file", file_path, xcresult,
    ]).decode("utf-8", errors="replace")

    result = []
    for line in raw.splitlines():
        stripped = line.lstrip()
        if not stripped or ":" not in stripped:
            continue
        head, _, _ = stripped.partition(":")
        try:
            line_num = int(head.strip())
        except ValueError:
            continue
        # Hits is the first whitespace-delimited token after the colon.
        after_colon = stripped.split(":", 1)[1].lstrip()
        hits_token = after_colon.split(None, 1)[0] if after_colon else ""
        if hits_token == "*" or hits_token == "":
            continue
        try:
            hits = int(hits_token)
        except ValueError:
            continue
        result.append((line_num, hits > 0))
    return result


if __name__ == "__main__":
    sys.exit(main())
