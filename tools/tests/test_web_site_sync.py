import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/web'))
import site_sync as sync
from deploy_vercel import SUITES

SHA = 'a' * 40

class WebSiteSyncTest(unittest.TestCase):
    def run_info(self):
        return {'repository': {'full_name': sync.REPOSITORY, 'private': True},
                'head_repository': {'full_name': sync.REPOSITORY},
                'head_branch': 'main', 'head_sha': SHA, 'event': 'push',
                'path': sync.WORKFLOW_PATH, 'status': 'completed', 'conclusion': 'success'}

    def fixture(self, root):
        release = root / 'release'
        release.mkdir()
        evidence = root / 'evidence'
        (evidence / 'web-browser-evidence').mkdir(parents=True)
        (evidence / 'web-release-evidence').mkdir()
        files = {}
        for name in ('index.html', 'index.js', 'index.pck', 'index.wasm', 'index.storage.js'):
            data = ('fixture:' + name).encode()
            (release / name).write_bytes(data)
            files[name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        meta = {'commit': SHA, 'version': 'test', 'debug': False, 'source_dirty': False,
                'built_at': 'test-build', 'files': files}
        (release / 'build.json').write_text(json.dumps(meta))
        browser = {'success': True, 'checks': [{'pass': True}], 'errors': [],
                   'build': {k: v for k, v in meta.items() if k != 'files'}}
        build = {'original_source_unchanged': True, 'rule_suites_executed': list(SUITES), 'build': meta}
        (evidence / 'web-browser-evidence/browser-checks.json').write_text(json.dumps(browser))
        (evidence / 'web-release-evidence/build-result.json').write_text(json.dumps(build))
        return release, evidence

    def placeholder(self, root):
        (root / 'public').mkdir(parents=True)
        (root / 'public/index.html').write_text('placeholder')
        (root / 'vercel.json').write_text('{}')
        (root / 'site-branch.json').write_text(json.dumps(sync.MARKER))

    def test_trusted_run_and_stale_run(self):
        self.assertTrue(sync.eligible_run(self.run_info(), SHA))
        self.assertFalse(sync.eligible_run(self.run_info(), 'b' * 40))

    def test_pr_fork_failure_and_other_workflow_rejected(self):
        for field, value in [('head_branch', 'feature'), ('event', 'pull_request'),
                             ('path', '.github/workflows/other.yml'), ('conclusion', 'failure'),
                             ('status', 'in_progress'), ('repository', {'full_name': 'other/repo'}),
                             ('head_repository', {'full_name': 'fork/repo'}), ('repository', {'full_name': sync.REPOSITORY, 'private': False})]:
            run = self.run_info()
            run[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                sync.eligible_run(run, SHA)

    def test_manual_web_run_on_main_allowed(self):
        run = self.run_info()
        run['event'] = 'workflow_dispatch'
        self.assertTrue(sync.eligible_run(run, SHA))

    def test_exact_runtime_package_and_headers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            release, evidence = self.fixture(root)
            (release / 'private.md').write_text('not publishable')
            output = root / 'package'
            result = sync.prepare(release, evidence, SHA, 123, output)
            self.assertFalse(result['hosting_verified'])
            self.assertFalse((output / 'public/private.md').exists())
            self.assertTrue((output / 'public/index.storage.js').is_file())
            config = json.loads((output / 'vercel.json').read_text())
            self.assertEqual(config['outputDirectory'], 'public')
            headers = config['headers'][0]['headers']
            self.assertIn({'key': 'Cross-Origin-Opener-Policy', 'value': 'same-origin'}, headers)
            self.assertIn({'key': 'Cross-Origin-Embedder-Policy', 'value': 'require-corp'}, headers)

    def test_same_commit_different_manifest_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            release, evidence = self.fixture(root)
            path = release / 'build.json'
            meta = json.loads(path.read_text())
            meta['built_at'] = 'other-build'
            path.write_text(json.dumps(meta))
            with self.assertRaises(ValueError):
                sync.prepare(release, evidence, SHA, 123, root / 'package')
            self.assertFalse((root / 'package').exists())

    def test_failed_browser_and_modified_runtime_rejected(self):
        for tamper in ('browser', 'runtime'):
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                release, evidence = self.fixture(root)
                if tamper == 'runtime':
                    (release / 'index.pck').write_bytes(b'changed')
                else:
                    path = evidence / 'web-browser-evidence/browser-checks.json'
                    data = json.loads(path.read_text())
                    data['success'] = False
                    path.write_text(json.dumps(data))
                with self.assertRaises(ValueError):
                    sync.prepare(release, evidence, SHA, 123, root / 'package')

    def test_existing_output_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            release, evidence = self.fixture(root)
            output = root / 'package'
            output.mkdir()
            with self.assertRaises(ValueError):
                sync.prepare(release, evidence, SHA, 123, output)

    def test_expected_branch_updated_and_git_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            release, evidence = self.fixture(root)
            output, target = root / 'package', root / 'site'
            sync.prepare(release, evidence, SHA, 123, output)
            self.placeholder(target)
            (target / '.git').mkdir()
            (target / '.git/keep').write_text('git data')
            sync.replace_site(output, target)
            self.assertEqual((target / '.git/keep').read_text(), 'git data')
            self.assertEqual((target / 'public/index.wasm').read_bytes(), (release / 'index.wasm').read_bytes())

    def test_foreign_branch_is_not_deleted(self):
        for mutation in ('unmarked', 'source-file', 'wrong-repo', 'symlink'):
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                release, evidence = self.fixture(root)
                output, target = root / 'package', root / 'site'
                sync.prepare(release, evidence, SHA, 123, output)
                self.placeholder(target)
                if mutation == 'unmarked':
                    (target / 'site-branch.json').unlink()
                elif mutation == 'source-file':
                    (target / 'AGENTS.md').write_text('never remove')
                elif mutation == 'wrong-repo':
                    marker = {**sync.MARKER, 'repository': 'other/repo'}
                    (target / 'site-branch.json').write_text(json.dumps(marker))
                else:
                    (target / 'public/index.js').symlink_to(root / 'outside')
                with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                    sync.replace_site(output, target)
                self.assertEqual((target / 'public/index.html').read_text(), 'placeholder')

    def test_tampered_package_is_not_copied(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            release, evidence = self.fixture(root)
            output, target = root / 'package', root / 'site'
            sync.prepare(release, evidence, SHA, 123, output)
            self.placeholder(target)
            (output / 'public/index.js').write_bytes(b'changed after prepare')
            with self.assertRaises(ValueError):
                sync.replace_site(output, target)
            self.assertEqual((target / 'public/index.html').read_text(), 'placeholder')

    def test_source_import_configuration_is_placeholder_only(self):
        config = json.loads((ROOT / 'vercel.json').read_text())
        self.assertEqual(config['outputDirectory'], 'hosting/placeholder')
        self.assertEqual(config['buildCommand'], '')
        self.assertEqual(config['installCommand'], '')
        self.assertEqual([p.name for p in (ROOT / config['outputDirectory']).iterdir()], ['index.html'])

if __name__ == '__main__':
    unittest.main()
