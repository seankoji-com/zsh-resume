"""Worktree discovery must remain useful when Git stalls."""
import importlib.machinery
import importlib.util
import contextlib
import io
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest import mock

SOURCE = Path(__file__).resolve().parents[1] / 'bin/resume-sessions'
LOADER = importlib.machinery.SourceFileLoader('resume_worktree_fixture', str(SOURCE))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
COLLECTOR = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(COLLECTOR)


class WorktreeTimeoutTest(unittest.TestCase):
    def test_stalled_git_returns_root_and_keeps_its_sessions(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / 'repo'
            root.mkdir()
            git = Path(td) / 'git'
            git.write_text('#!/bin/sh\nexec /bin/sleep 3\n')
            git.chmod(0o755)
            stderr = io.StringIO()
            with mock.patch.dict(os.environ, {'PATH': td}), \
                    mock.patch.object(COLLECTOR, 'GIT_WORKTREE_TIMEOUT', 0.2), \
                    contextlib.redirect_stderr(stderr):
                start = time.monotonic()
                dirs = COLLECTOR.repo_dirs(str(root))
                elapsed = time.monotonic() - start
            self.assertLess(elapsed, 2)
            self.assertEqual(dirs, {str(root)})
            self.assertIn('timed out', stderr.getvalue())
            self.assertTrue(COLLECTOR.scope(dirs)(str(root / 'project')))
            self.assertFalse(COLLECTOR.scope(dirs)(str(Path(td) / 'elsewhere')))

    def test_success_includes_registered_worktree(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / 'repo'
            root.mkdir()
            git = Path(td) / 'git'
            git.write_text('#!/bin/sh\nprintf "worktree %s\\nworktree %s\\n" "$2" "$2-sibling"\n')
            git.chmod(0o755)
            with mock.patch.dict(os.environ, {'PATH': td}):
                dirs = COLLECTOR.repo_dirs(str(root))
            self.assertEqual(dirs, {str(root), str(root) + '-sibling'})


if __name__ == '__main__':
    unittest.main()
