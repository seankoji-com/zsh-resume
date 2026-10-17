"""A disappearing session must not stop a reader before the next valid file."""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


SOURCE = Path(__file__).resolve().parents[1] / 'bin/resume-sessions'
LOADER = importlib.machinery.SourceFileLoader('resume_stat_fixture', str(SOURCE))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
COLLECTOR = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(COLLECTOR)


class DisappearingSessionTest(unittest.TestCase):
    def test_each_file_reader_continues_after_a_stat_failure(self):
        cases = [
            ('claude', COLLECTOR.read_claude, 'claude/{id}.jsonl', '*.jsonl'),
            ('codex', COLLECTOR.read_codex, 'codex/rollout-{id}.jsonl', 'rollout-*.jsonl'),
            ('grok', COLLECTOR.read_grok, 'grok/{id}/summary.json', 'summary.json'),
            ('kiro-current', COLLECTOR.read_kiro, 'kiro/sess_{id}/session.json', 'session.json'),
            ('kiro-legacy', COLLECTOR.read_kiro, 'kiro/{id}.json', '*.json'),
        ]
        for tool, reader, layout, pattern in cases:
            with self.subTest(tool=tool), tempfile.TemporaryDirectory() as td:
                root = Path(td)
                paths = []
                for sid in ('vanished', 'healthy'):
                    path = root / layout.format(id=sid)
                    path.parent.mkdir(parents=True, exist_ok=True)
                    payload = {
                        'claude': {'type': 'user', 'cwd': '/fixture/repo', 'message': {'content': sid}},
                        'codex': {'type': 'session_meta', 'payload': {'id': sid, 'cwd': '/fixture/repo'}},
                        'grok': {'info': {'id': sid, 'cwd': '/fixture/repo'}},
                        'kiro-current': {'id': sid, 'workspacePaths': ['/fixture/repo']},
                        'kiro-legacy': {'session_id': sid, 'cwd': '/fixture/repo'},
                    }[tool]
                    path.write_text(json.dumps(payload) + '\n')
                    paths.append(str(path))

                def matching_paths(glob_pattern):
                    return paths if glob_pattern.endswith(pattern) else []

                def modification_time(path):
                    if str(path) == paths[0]:
                        raise FileNotFoundError('fixture disappeared after reading')
                    return 123.0

                with mock.patch.object(COLLECTOR, 'home', side_effect=lambda *p: str(root.joinpath(*p))), \
                        mock.patch.object(COLLECTOR.glob, 'glob', side_effect=matching_paths), \
                        mock.patch.object(COLLECTOR.os.path, 'getmtime', side_effect=modification_time), \
                        contextlib.redirect_stderr(io.StringIO()):
                    found = list(reader(lambda cwd: True))
                self.assertEqual([row[1] for row in found], ['healthy'])
                self.assertEqual(found[0][2], 123.0)


if __name__ == '__main__':
    unittest.main()
