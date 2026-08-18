#!/usr/bin/env python3
"""Convert SimpleCov's JSON result into line-only Cobertura XML."""

from __future__ import annotations

import argparse
import fnmatch
import json
import xml.etree.ElementTree as ET
from pathlib import Path


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pathspec", action="append", required=True)
    return parser.parse_args()


def get_coverage(result: dict[str, object]) -> dict[str, list[int | None]]:
    coverage: dict[str, list[int | None]] = {}
    for command in result.values():
        files = command.get("coverage", {})
        for filename, details in files.items():
            lines = details.get("lines", details) if isinstance(details, dict) else details
            current = coverage.setdefault(filename, [None] * len(lines))
            if len(current) < len(lines):
                current.extend([None] * (len(lines) - len(current)))
            for index, hits in enumerate(lines):
                if hits is None:
                    continue
                current[index] = int(hits) + int(current[index] or 0)
    return coverage


def executable_line_numbers(source: Path) -> set[int]:
    executable: set[int] = set()
    in_single = False
    in_double = False

    for number, raw_line in enumerate(source.read_text(encoding="utf-8").splitlines(), start=1):
        index = 0
        saw_code = False
        saw_unquoted_nonspace = False

        while index < len(raw_line):
            char = raw_line[index]
            escaped = index > 0 and raw_line[index - 1] == "\\"

            if in_single:
                if char == "'":
                    in_single = False
                index += 1
                continue

            if in_double:
                if char == '"' and not escaped:
                    in_double = False
                index += 1
                continue

            if char in " \t":
                index += 1
                continue
            if char == "#":
                break

            saw_code = True
            if char == "'":
                in_single = True
            elif char == '"' and not escaped:
                in_double = True
            else:
                saw_unquoted_nonspace = True
            index += 1

        if saw_unquoted_nonspace or (saw_code and not in_single and not in_double):
            executable.add(number)

    return executable


def build_cobertura(
    coverage: dict[str, list[int | None]], repo: Path, pathspecs: list[str]
) -> ET.ElementTree:
    root = ET.Element("coverage")
    classes = ET.SubElement(ET.SubElement(ET.SubElement(root, "packages"), "package"), "classes")
    for filename, hits_by_line in sorted(coverage.items()):
        path = Path(filename).resolve()
        try:
            relative_path = path.relative_to(repo.resolve()).as_posix()
        except ValueError:
            continue
        if not any(fnmatch.fnmatch(relative_path, pathspec) for pathspec in pathspecs):
            continue
        executable_lines = executable_line_numbers(path)
        class_node = ET.SubElement(classes, "class", filename=relative_path)
        lines_node = ET.SubElement(class_node, "lines")
        for number, hits in enumerate(hits_by_line, start=1):
            if hits is not None and number in executable_lines:
                ET.SubElement(lines_node, "line", number=str(number), hits=str(hits))
    return ET.ElementTree(root)


def main() -> int:
    arguments = parse_arguments()
    raw_result = json.loads(arguments.input.read_text(encoding="utf-8"))
    tree = build_cobertura(get_coverage(raw_result), arguments.repo, arguments.pathspec)
    ET.indent(tree, space="  ")
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    tree.write(arguments.output, encoding="utf-8", xml_declaration=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
