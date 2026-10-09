"""Negative tests for archival assertions. No archived program is executed."""
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('archive', Path(__file__).resolve().parents[1] / 'validate_archive.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class ArchiveChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for name in mod.REQUIRED:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('# Current document\n', encoding='utf-8')
        self.inv = {'authoritative_repository':'xlbaoxl/canghuo-combat', 'artifacts':[], 'unlocated_originals':[]}
        self.save_inventory()
    def tearDown(self):
        self.tmp.cleanup()
    def save_inventory(self):
        (self.root / 'migration/artifact_inventory.json').write_text(json.dumps(self.inv), encoding='utf-8')
    def add_package(self):
        base = 'research/originals/example'
        raw = b'# Original\r\n[table](evidence.csv)\r\n'
        (self.root / base).mkdir(parents=True)
        (self.root / base / 'README.md').write_bytes(raw)
        self.pkg = {'source_artifact':'example.zip', 'source_prefix':'example/', 'archive_root':base, 'total_members':2, 'members':[
            {'member':'README.md', 'destination':base+'/README.md', 'status':'archived', 'transform':'identity', 'source_bytes':len(raw), 'source_sha256':hashlib.sha256(raw).hexdigest(), 'archived_bytes':len(raw), 'archived_sha256':hashlib.sha256(raw).hexdigest()},
            {'member':'evidence.csv', 'destination':base+'/evidence.csv', 'status':'pending', 'source_bytes':3, 'source_sha256':hashlib.sha256(b'a\r\n').hexdigest()}]}
        self.save_package()
    def save_package(self):
        (self.root / 'migration/research_members.json').write_text(json.dumps({'packages':[self.pkg]}), encoding='utf-8')
    def test_empty_integrity_does_not_imply_migration(self):
        r = mod.validate(self.root)
        self.assertEqual(r['status'], 'PASS')
        self.assertFalse(r['migration_complete'])
        self.assertFalse(r['gameplay_or_godot_executed'])
    def test_strict_completion_rejects_missing_source(self):
        self.assertEqual(mod.validate(self.root, require_complete=True)['status'], 'FAIL')
    def test_current_broken_link_fails(self):
        (self.root / 'README.md').write_text('[lost](absent.md)\n')
        self.assertEqual(mod.validate(self.root)['status'], 'FAIL')
    def test_declared_historical_gap_is_explicit(self):
        self.add_package()
        r = mod.validate(self.root)
        self.assertEqual(r['status'], 'PASS')
        self.assertEqual(len(r['pending_research_members']), 1)
        self.assertEqual(len(r['deferred_historical_links']), 1)
        self.assertFalse(r['migration_complete'])
    def test_current_doc_cannot_use_pending_exception(self):
        self.add_package()
        (self.root / 'README.md').write_text('[missing](research/originals/example/evidence.csv)')
        self.assertEqual(mod.validate(self.root)['status'], 'FAIL')
    def test_unknown_historical_gap_is_error(self):
        self.add_package()
        self.pkg['members'][1]['destination'] = 'research/originals/example/other.csv'
        self.pkg['members'][1]['member'] = 'other.csv'
        self.save_package()
        self.assertEqual(mod.validate(self.root)['status'], 'FAIL')
    def test_changed_original_fails(self):
        self.add_package()
        with (self.root / self.pkg['members'][0]['destination']).open('ab') as f:
            f.write(b'changed')
        self.assertEqual(mod.validate(self.root)['status'], 'FAIL')
    def test_crlf_normalization_is_not_identity(self):
        self.add_package()
        path = self.root / self.pkg['members'][0]['destination']
        path.write_bytes(path.read_bytes().replace(b'\r\n', b'\n'))
        self.assertEqual(mod.validate(self.root)['status'], 'FAIL')
    def test_archived_missing_fails(self):
        self.add_package()
        (self.root / self.pkg['members'][0]['destination']).unlink()
        self.assertEqual(mod.validate(self.root)['status'], 'FAIL')
    def test_false_pending_fails(self):
        self.add_package()
        (self.root / self.pkg['members'][1]['destination']).write_bytes(b'a\r\n')
        self.assertEqual(mod.validate(self.root)['status'], 'FAIL')
    def test_manifest_escape_rejected(self):
        self.add_package()
        self.pkg['members'][1]['destination'] = '../outside.csv'
        self.save_package()
        with self.assertRaises(ValueError):
            mod.validate(self.root)
    def test_link_escape_rejected(self):
        (self.root / 'README.md').write_text('[escape](../outside.md)')
        self.assertEqual(mod.validate(self.root)['status'], 'FAIL')
    def test_unbalanced_fence_rejected(self):
        (self.root / 'README.md').write_text('```text\nexample\n')
        self.assertEqual(mod.validate(self.root)['status'], 'FAIL')
    def test_claimed_full_artifact_hash_checked(self):
        raw = b'original'
        (self.root / 'research/original.txt').write_bytes(raw)
        self.inv['artifacts'] = [{'name':'original.txt', 'bytes':len(raw), 'sha256':'0'*64, 'repository_copy':'research/original.txt'}]
        self.save_inventory()
        self.assertEqual(mod.validate(self.root)['status'], 'FAIL')
    def test_duplicate_member_rejected(self):
        self.add_package()
        self.pkg['members'].append(dict(self.pkg['members'][0]))
        self.pkg['total_members'] = 3
        self.save_package()
        self.assertEqual(mod.validate(self.root)['status'], 'FAIL')
    def test_no_forged_original_for_complete(self):
        self.add_package()
        self.assertEqual(mod.validate(self.root, require_complete=True)['status'], 'FAIL')

if __name__ == '__main__':
    unittest.main()
