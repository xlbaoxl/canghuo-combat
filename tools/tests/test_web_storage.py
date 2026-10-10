"""Execute the same browser save acknowledgement code in Node, including failure cases."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]

class WebStorageTests(unittest.TestCase):
    def test_readback_and_failure_boundaries(self):
        result = subprocess.run(['node', str(ROOT / 'tools/web/test_storage.cjs')],
                                cwd=ROOT, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('STORAGE_ACK checks=9 failures=0', result.stdout)
