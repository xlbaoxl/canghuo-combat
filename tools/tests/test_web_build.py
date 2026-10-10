import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('web_build', ROOT / 'tools/web/build.py')
web = importlib.util.module_from_spec(spec)
spec.loader.exec_module(web)

class WebBuildTest(unittest.TestCase):
    def test_staging_keeps_rules_and_assets_identical(self):
        original = web.fingerprints(web.SOURCE)
        with tempfile.TemporaryDirectory() as temporary:
            stage = Path(temporary) / 'project'
            web.prepare(stage, {'commit': 'test', 'version': 'test'})
            staged = web.fingerprints(stage)
            changed = sorted(name for name, digest in original.items() if staged.get(name) != digest)
            self.assertEqual(changed, ['export_presets.cfg', 'project.godot'])
            self.assertIn('gl_compatibility', (stage / 'project.godot').read_text())
            self.assertIn('variant/thread_support=true', (stage / 'export_presets.cfg').read_text())
            self.assertEqual(json.loads((stage / 'web/build.json').read_text())['commit'], 'test')
            self.assertIn('extends "res://scripts/main.gd"', (stage / 'web/main.gd').read_text())
        self.assertEqual(original, web.fingerprints(web.SOURCE))

    def test_existing_staging_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(ValueError):
                web.prepare(Path(temporary), {})

    def test_headers_allow_existing_ai_threads(self):
        self.assertEqual(web.HEADERS['Cross-Origin-Opener-Policy'], 'same-origin')
        self.assertEqual(web.HEADERS['Cross-Origin-Embedder-Policy'], 'require-corp')
        self.assertEqual(web.HEADERS['Cache-Control'], 'no-cache')

    def test_no_service_worker_or_automatic_reload(self):
        shell = (web.ADAPTER / 'shell.html').read_text()
        self.assertNotIn('serviceWorker.register', shell)
        self.assertIn("if(confirm(", shell)
        self.assertIn("cache:'no-store'", shell)
        self.assertIn("navigator.clipboard.writeText", shell)
        self.assertIn("textContent=", shell)
        self.assertNotIn('innerHTML', shell)

if __name__ == '__main__':
    unittest.main()
