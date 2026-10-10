import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('deploy_vercel', ROOT / 'tools/web/deploy_vercel.py')
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)
COMMIT = 'a' * 40

class FakeClient:
    def __init__(self, protection='all'):
        self.calls = []
        self.protection = protection
    def request(self, method, path, data=None, extra=None):
        self.calls.append((method, path, data, extra))
        if path.startswith('/v9/projects/'):
            return {'id': 'prj_test', 'name': 'test', 'ssoProtection': {'deploymentType': self.protection}}
        if path == '/v13/deployments':
            return {'id': 'dpl_test', 'readyState': 'READY', 'url': 'test.vercel.app', 'alias': []}
        return {}

class WebDeployTest(unittest.TestCase):
    def fixture(self, root):
        files = {}
        for name in ['index.html', 'index.js', 'index.wasm', 'index.pck']:
            data = ('test-' + name).encode()
            (root / name).write_bytes(data)
            files[name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        meta = {'commit': COMMIT, 'version': 'test', 'debug': False, 'source_dirty': False, 'files': files}
        browser = {'build': meta, 'success': True, 'errors': [], 'checks': [{'pass': True}]}
        build = {'build': meta, 'original_source_unchanged': True, 'rule_suites_executed': list(deploy.SUITES)}
        for name, obj in [('build.json', meta), ('browser.json', browser), ('evidence.json', build)]:
            (root / name).write_text(json.dumps(obj))
        return meta, browser, build

    def verify(self, root):
        return deploy.verified_files(root, root / 'browser.json', root / 'evidence.json', COMMIT)

    def test_verified_export_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            (root / 'private-design.md').write_text('must not upload')
            meta, files = self.verify(root)
            self.assertNotIn('private-design.md', files)
            self.assertNotIn('browser.json', files)
            config = json.loads(files['vercel.json'])
            self.assertIn({'key': 'Cross-Origin-Embedder-Policy', 'value': 'require-corp'}, config['headers'][0]['headers'])
            client = FakeClient()
            receipt = deploy.deploy(client, 'prj_test', meta, files)
            self.assertTrue(receipt['hosting_ready'])
            self.assertFalse(receipt['public_http_and_browser_verified'])
            self.assertNotIn('target', client.calls[-1][2])

    def test_unprotected_project_makes_no_writes(self):
        for mode in [None, 'preview', 'prod_deployment_urls_and_all_previews']:
            client = FakeClient(mode)
            with self.assertRaises(ValueError):
                deploy.deploy(client, 'prj_test', {'commit': COMMIT}, {'index.html': b'test'}, True)
            self.assertEqual([call[0] for call in client.calls], ['GET'])

    def test_unverified_stale_or_dirty_export_rejected(self):
        for filename, field, value in [('browser.json', 'success', False), ('browser.json', 'checks', []), ('build.json', 'commit', 'b' * 40), ('build.json', 'source_dirty', True), ('evidence.json', 'rule_suites_executed', [])]:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.fixture(root)
                obj = json.loads((root / filename).read_text())
                obj[field] = value
                (root / filename).write_text(json.dumps(obj))
                with self.assertRaises(ValueError):
                    self.verify(root)

    def test_tampered_file_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            (root / 'index.pck').write_bytes(b'changed')
            with self.assertRaises(ValueError):
                self.verify(root)

    def test_path_escape_and_symlink_rejected(self):
        for name in ['../secret', 'code.gd', 'index.gd']:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                meta, _, _ = self.fixture(root)
                meta['files'][name] = {'bytes': 1, 'sha256': 'a' * 64}
                (root / 'build.json').write_text(json.dumps(meta))
                with self.assertRaises(ValueError):
                    self.verify(root)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            (root / 'index.pck').unlink()
            (root / 'index.pck').symlink_to(root / 'index.js')
            with self.assertRaises(ValueError):
                self.verify(root)

    def test_no_missing_credentials_or_project_auto_creation(self):
        with self.assertRaises(ValueError):
            deploy.Client('')
        client = FakeClient()
        with self.assertRaises(ValueError):
            deploy.deploy(client, 'new-project-name', {}, {})
        self.assertEqual(client.calls, [])

if __name__ == '__main__':
    unittest.main()
