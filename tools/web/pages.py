#!/usr/bin/env python3
"""Add a network-only isolation adapter to an actual, freshly verified Web export.
The authoritative Godot PCK/WASM and embedded build identity stay unchanged.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / 'modules/training-camp/web'


def fingerprint(data: bytes) -> dict:
    return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def prepare(root: Path, evidence: Path, adapter: Path = ADAPTER) -> dict:
    if root.is_symlink() or not root.is_dir():
        raise ValueError('Expected an actual export directory')
    meta = json.loads((root / 'build.json').read_text(encoding='utf-8'))
    build_path = evidence / 'build-result.json'
    report = json.loads(build_path.read_text(encoding='utf-8'))
    if not re.fullmatch('[0-9a-f]{40}', meta.get('commit', '')) or meta.get('source_dirty') or meta.get('debug'):
        raise ValueError('Expected a clean release with an exact source commit')
    if report.get('build') != meta or report.get('original_source_unchanged') is not True:
        raise ValueError('Original export and build evidence disagree')
    files = meta.get('files', {})
    for name, expected in files.items():
        if not re.fullmatch(r'index(?:\.[a-z0-9_-]+)+', name):
            raise ValueError('Unexpected export filename')
        p = root / name
        if p.is_symlink() or not p.is_file() or fingerprint(p.read_bytes()) != expected:
            raise ValueError('Original export fingerprint mismatch: ' + name)
    if not {'index.html', 'index.js', 'index.wasm', 'index.pck', 'index.storage.js'}.issubset(files):
        raise ValueError('Incomplete export')
    html = (root / 'index.html').read_text(encoding='utf-8')
    needle = '<script src="index.storage.js"></script>'
    if html.count(needle) != 1 or 'index.isolation.js' in html:
        raise ValueError('Unexpected or already adapted HTML shell')
    additions = {f'index.{name}': (adapter / name).read_bytes()
                 for name in ('isolation.js', 'isolation.worker.js')}
    if any((root / name).exists() for name in additions):
        raise ValueError('Refusing to overwrite an existing adapter')
    html = html.replace(needle, '<script src="index.isolation.js"></script>\n' + needle)
    updated = {'index.html': html.encode('utf-8'), **additions}
    # All validation above completes before any export file is changed.
    original_html = files['index.html']['sha256']
    for name, data in updated.items():
        (root / name).write_bytes(data)
        meta['files'][name] = fingerprint(data)
    (root / 'build.json').write_text(json.dumps(meta, indent=2) + '\n', encoding='utf-8')
    receipt = {'adapter': 'network-only-isolation-1', 'commit': meta['commit'],
               'original_html_sha256': original_html, 'changed_files': list(updated),
               'game_pack_unchanged': True, 'browser_verified': False, 'hosting_deployed': False}
    report['build'] = meta
    report['pages_adapter'] = receipt
    build_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    (evidence / 'pages-adapter.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--evidence', required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.root.resolve(), args.evidence.resolve()), indent=2))
