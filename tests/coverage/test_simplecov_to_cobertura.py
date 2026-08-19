from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("simplecov_to_cobertura.py")
SPEC = importlib.util.spec_from_file_location("simplecov_to_cobertura", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class SimpleCovToCoberturaTests(unittest.TestCase):
    def test_get_coverage_merges_commands_and_preserves_non_executable_lines(self):
        result = {
            "first": {"coverage": {"/repo/lib/a.sh": {"lines": [None, 1, 0]}}},
            "second": {"coverage": {"/repo/lib/a.sh": {"lines": [None, 2, None, 1]}}},
        }

        coverage = MODULE.get_coverage(result)

        self.assertEqual(coverage, {"/repo/lib/a.sh": [None, 3, 0, 1]})

    def test_build_cobertura_writes_only_matching_repo_executable_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            source = repo / "lib" / "a.sh"
            source.parent.mkdir()
            source.write_text("#!/bin/bash\ntrue\nfalse\n", encoding="utf-8")
            coverage = {
                str(source): [None, 2, 0],
                "/outside/b.sh": [1],
            }

            root = MODULE.build_cobertura(coverage, repo, ["lib/*.sh"]).getroot()

        class_nodes = root.findall(".//class")
        self.assertEqual([node.get("filename") for node in class_nodes], ["lib/a.sh"])
        self.assertEqual(
            [(node.get("number"), node.get("hits")) for node in root.findall(".//line")],
            [("2", "2"), ("3", "0")],
        )

    def test_build_cobertura_ignores_comment_and_multiline_string_body_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            source = repo / "scripts" / "sample.sh"
            source.parent.mkdir()
            source.write_text(
                "#!/usr/bin/env bash\n"
                "echo before\n"
                "cmd '\n"
                "  body only\n"
                "  still body\n"
                "' | cat\n"
                "# trailing comment\n",
                encoding="utf-8",
            )
            coverage = {
                str(source): [None, 1, 1, 0, 0, 1, 0],
            }

            root = MODULE.build_cobertura(coverage, repo, ["scripts/*.sh"]).getroot()

        self.assertEqual(
            [(node.get("number"), node.get("hits")) for node in root.findall(".//line")],
            [("2", "1"), ("3", "1"), ("6", "1")],
        )

    def test_build_cobertura_ignores_heredoc_body_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            source = repo / "scripts" / "sample.sh"
            source.parent.mkdir()
            source.write_text(
                "#!/usr/bin/env bash\n"
                "cat <<'EOF'\n"
                "usage text\n"
                "more usage text\n"
                "EOF\n"
                "echo after\n",
                encoding="utf-8",
            )
            coverage = {
                str(source): [None, 1, 0, 0, 0, 1],
            }

            root = MODULE.build_cobertura(coverage, repo, ["scripts/*.sh"]).getroot()

        self.assertEqual(
            [(node.get("number"), node.get("hits")) for node in root.findall(".//line")],
            [("2", "1"), ("6", "1")],
        )


if __name__ == "__main__":
    unittest.main()
