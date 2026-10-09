#!/usr/bin/env python3
"""Restore only explicitly inventoried CRLF originals, after exact byte checks.
No source is downloaded. Every proposed output must match the pre-existing
original SHA256 and size before any file is written. Metadata keeps provenance.
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
manifest_path = ROOT / 'migration/research_members.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
prepared = []
for package in manifest['packages']:
    for row in package['members']:
        if row['status'] != 'archived' or row.get('transform') != 'crlf_to_lf':
            continue
        name = row['destination']
        path = ROOT / name
        if not name.startswith('research/originals/') or '..' in Path(name).parts or not path.resolve().is_relative_to(ROOT) or path.is_symlink():
            raise ValueError('Unsafe original path: ' + name)
        before = path.read_bytes()
        if len(before) != row['archived_bytes'] or hashlib.sha256(before).hexdigest() != row['archived_sha256']:
            raise ValueError('Concurrent change or wrong archived original: ' + name)
        after = before.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
        if len(after) != row['source_bytes'] or hashlib.sha256(after).hexdigest() != row['source_sha256']:
            raise ValueError('Cannot recover exact original; refusing to invent content: ' + name)
        prepared.append((path, after))
        row['previous_archive'] = {'transform': row['transform'], 'bytes': row['archived_bytes'], 'sha256': row['archived_sha256']}
        row['transform'] = 'identity'
        row['archived_bytes'] = row['source_bytes']
        row['archived_sha256'] = row['source_sha256']
for path, data in prepared:
    path.write_bytes(data)
if prepared:
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(json.dumps({'restored_originals': len(prepared), 'files': [str(p.relative_to(ROOT)) for p, _ in prepared], 'source_code_or_gameplay_changed': False}, ensure_ascii=False))
