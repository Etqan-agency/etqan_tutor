"""commands.run: stdout vs stderr, and clean failures for a bad cwd (spec 2026-10-03 §4.1)."""

import sys
import unittest
from pathlib import Path

from orchestra_server import commands


class Run(unittest.TestCase):
    def test_a_successful_run_returns_stdout_only(self):
        output = commands.run([sys.executable, "-c", "import sys; print('data'); print('warn', file=sys.stderr)"])
        self.assertEqual(output, "data\n")

    def test_a_failed_runs_tail_has_both_stdout_and_stderr(self):
        with self.assertRaises(commands.CommandFailed) as ctx:
            commands.run([sys.executable, "-c", "import sys; print('out'); print('err', file=sys.stderr); sys.exit(1)"])
        self.assertEqual(ctx.exception.payload["output_tail"], "out\nerr")

    def test_a_cwd_that_is_a_file_is_reported_as_itself_not_as_not_found(self):
        bad_cwd = Path(__file__)  # a file, not a directory
        with self.assertRaises(commands.CommandFailed) as ctx:
            commands.run([sys.executable, "-c", "pass"], cwd=bad_cwd)
        tail = ctx.exception.payload["output_tail"]
        self.assertIn(str(bad_cwd), tail)
        self.assertNotIn("not found", tail)
