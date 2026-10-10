import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('pages_adapter', ROOT / 'tools/web/pages.py')
pages = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pages)

class PagesTest(unittest.TestCase):
    def fixture(self, directory):
        root = directory / 'release'; root.mkdir()
        evidence = directory / 'evidence'; evidence.mkdir()
        contents = {name: name.encode() for name in ['index.html', 'index.js', 'index.pck', 'index.wasm', 'index.storage.js']}
        contents['index.html'] = b'<script src="index.storage.js"></script>\n<script src="index.js"></script>'
        for name, data in contents.items(): (root / name).write_bytes(data)
        meta = {'version': 'test', 'commit': 'a'*40, 'debug': False, 'source_dirty': False,
                'files': {name: pages.fingerprint(data) for name, data in contents.items()}}
        report = {'build': meta, 'original_source_unchanged': True, 'rule_suites_executed': ['test_upgrade']}
        (root / 'build.json').write_text(json.dumps(meta))
        (evidence / 'build-result.json').write_text(json.dumps(report))
        return root, evidence, contents

    def test_only_shell_and_isolation_scripts_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, evidence, contents = self.fixture(Path(tmp))
            receipt = pages.prepare(root, evidence)
            for name in ['index.js', 'index.wasm', 'index.pck', 'index.storage.js']:
                self.assertEqual((root / name).read_bytes(), contents[name])
            self.assertFalse(receipt['hosting_deployed'])
            self.assertFalse(receipt['browser_verified'])
            meta = json.loads((root / 'build.json').read_text())
            self.assertEqual(meta, json.loads((evidence / 'build-result.json').read_text())['build'])
            for name, expected in meta['files'].items():
                self.assertEqual(pages.fingerprint((root / name).read_bytes()), expected)
            self.assertIn('index.isolation.worker.js', meta['files'])

    def test_tampered_package_fails_before_mutation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, evidence, contents = self.fixture(Path(tmp))
            (root / 'index.pck').write_bytes(b'tampered')
            with self.assertRaises(ValueError): pages.prepare(root, evidence)
            self.assertEqual((root / 'index.html').read_bytes(), contents['index.html'])
            self.assertFalse((root / 'index.isolation.js').exists())

    def test_mismatched_evidence_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, evidence, _ = self.fixture(Path(tmp))
            obj = json.loads((evidence / 'build-result.json').read_text())
            obj['build']['commit'] = 'b'*40
            (evidence / 'build-result.json').write_text(json.dumps(obj))
            with self.assertRaises(ValueError): pages.prepare(root, evidence)

    def test_dirty_or_debug_rejected(self):
        for flag in ['debug', 'source_dirty']:
            with tempfile.TemporaryDirectory() as tmp:
                root, evidence, _ = self.fixture(Path(tmp))
                meta = json.loads((root / 'build.json').read_text()); meta[flag] = True
                (root / 'build.json').write_text(json.dumps(meta))
                with self.assertRaises(ValueError): pages.prepare(root, evidence)

    def test_second_adaptation_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, evidence, _ = self.fixture(Path(tmp)); pages.prepare(root, evidence)
            with self.assertRaises(ValueError): pages.prepare(root, evidence)

    def test_worker_is_scoped_and_network_only(self):
        source = (pages.ADAPTER / 'isolation.worker.js').read_text()
        self.assertIn('url.pathname.startsWith(scope.pathname)', source)
        self.assertIn("cache: 'no-cache'", source)
        self.assertNotIn('caches.', source)
        self.assertIn("headers.set('Cross-Origin-Embedder-Policy', 'require-corp')", source)

    def test_reload_is_startup_only_and_bounded(self):
        source = (pages.ADAPTER / 'isolation.js').read_text()
        self.assertIn('sessionStorage.getItem(key)', source)
        self.assertIn("if (state.state === 'error') return", source)
        self.assertIn('window.canghuoStatus', source)
        self.assertIn("updateViaCache: 'none'", source)

if __name__ == '__main__': unittest.main()
