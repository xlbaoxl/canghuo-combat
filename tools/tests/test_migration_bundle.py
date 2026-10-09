"""Bundle preflight tests. No network, credentials, push or game execution."""
import hashlib
import importlib.util
import json
import stat
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('bundle', Path(__file__).resolve().parents[1] / 'apply_migration_bundle.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class MigrationBundleChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.root = self.base / 'repo'
        self.root.mkdir()
        self.bundle = self.base / 'bundle.zip'
    def tearDown(self):
        self.tmp.cleanup()
    def make(self, path='docs/example.md', base=None, bad_digest=False, extra=False, symlink=False, repository=None, local_source=False):
        data = b'# Original\r\n'
        manifest = {'format':1, 'repository':repository or mod.REPOSITORY, 'source_commit':'e101fca146bf340d8738dbaa3931c827e4efc227',
                    'files':[{'path':path, 'size':len(data), 'sha256':'0'*64 if bad_digest else hashlib.sha256(data).hexdigest(), 'base_sha256':base, 'mode':'100644'}]}
        if local_source:
            manifest['files'][0].update(storage='local_source', source_commit=mod.SOURCE_COMMIT, source_path=path)
        with zipfile.ZipFile(self.bundle, 'w') as z:
            z.writestr('migration-bundle.json', json.dumps(manifest))
            z.writestr('README.txt', 'test input only')
            info = zipfile.ZipInfo('payload/' + path)
            if symlink:
                info.create_system = 3
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
            if not local_source:
                z.writestr(info, data)
            if extra:
                z.writestr('payload/unlisted.py', b'not authorized')
        return data
    def test_valid_preflight_has_no_writes(self):
        self.make()
        _, files = mod.prepare(self.bundle, self.root)
        self.assertEqual(len(files), 1)
        self.assertEqual(list(self.root.iterdir()), [])
    def test_hash_mismatch(self):
        self.make(bad_digest=True)
        with self.assertRaises(ValueError): mod.prepare(self.bundle, self.root)
    def test_unlisted_payload(self):
        self.make(extra=True)
        with self.assertRaises(ValueError): mod.prepare(self.bundle, self.root)
    def test_wrong_repository(self):
        self.make(repository='other/private')
        with self.assertRaises(ValueError): mod.prepare(self.bundle, self.root)
    def test_path_escape(self):
        self.make(path='../outside')
        with self.assertRaises(ValueError): mod.prepare(self.bundle, self.root)
    def test_git_internals_rejected(self):
        self.make(path='.git/config')
        with self.assertRaises(ValueError): mod.prepare(self.bundle, self.root)
    def test_symlink_payload_rejected(self):
        self.make(symlink=True)
        with self.assertRaises(ValueError): mod.prepare(self.bundle, self.root)
    def test_concurrent_change_rejected(self):
        self.make(base=hashlib.sha256(b'old').hexdigest())
        (self.root/'docs').mkdir()
        (self.root/'docs/example.md').write_bytes(b'someone else changed this')
        with self.assertRaises(ValueError): mod.prepare(self.bundle, self.root)
    def test_exact_base_can_be_replaced(self):
        self.make(base=hashlib.sha256(b'old').hexdigest())
        (self.root/'docs').mkdir()
        (self.root/'docs/example.md').write_bytes(b'old')
        _, files = mod.prepare(self.bundle, self.root)
        self.assertEqual(len(files), 1)
        self.assertEqual((self.root/'docs/example.md').read_bytes(), b'old')
    def test_existing_identical_bytes_allowed(self):
        raw=self.make()
        (self.root/'docs').mkdir()
        (self.root/'docs/example.md').write_bytes(raw)
        self.assertEqual(len(mod.prepare(self.bundle, self.root)[1]), 1)
    def test_expected_deleted_file_is_not_silently_recreated(self):
        self.make(base=hashlib.sha256(b'old').hexdigest())
        with self.assertRaises(ValueError): mod.prepare(self.bundle, self.root)

    def test_missing_original_dependency_requires_local_source(self):
        self.make(path='modules/training-camp/project/assets/original.bin', local_source=True)
        with self.assertRaises(ValueError): mod.prepare(self.bundle, self.root)
    def test_existing_verified_original_dependency_is_reused(self):
        name='modules/training-camp/project/assets/original.bin'
        raw=self.make(path=name, local_source=True)
        target=self.root/name
        target.parent.mkdir(parents=True)
        target.write_bytes(raw)
        self.assertEqual(len(mod.prepare(self.bundle, self.root)[1]), 1)

if __name__ == '__main__': unittest.main()
