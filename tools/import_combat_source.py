#!/usr/bin/env python3
"""Import the author-approved 3.0.1 combat snapshot without changing its runtime.
No source checkout credentials are needed: a short-lived, exact artifact URL may
be supplied out-of-band. The archive and every source blob are verified first.
"""
from __future__ import annotations
import argparse, hashlib, io, json, os, stat, sys, urllib.parse, urllib.request, zipfile
from pathlib import Path, PurePosixPath

SOURCE = 'e101fca146bf340d8738dbaa3931c827e4efc227'
OUTER_SHA = '809a9a12d09dec39420329e4f21ee989ad2194c7c4c0f1181ba64ddd6b933455'
MAX_BYTES = 100 * 1024 * 1024


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def members(archive: zipfile.ZipFile) -> dict:
    result = {}
    total = 0
    for item in archive.infolist():
        path = PurePosixPath(item.filename)
        if path.is_absolute() or '..' in path.parts or '\\' in item.filename:
            raise ValueError('Unsafe archive path')
        if stat.S_ISLNK(item.external_attr >> 16):
            raise ValueError('Symlinks are not accepted')
        if item.is_dir():
            continue
        if item.filename in result:
            raise ValueError('Duplicate archive member')
        total += item.file_size
        if total > MAX_BYTES or item.file_size > MAX_BYTES:
            raise ValueError('Archive exceeds its approved size bound')
        result[item.filename] = item
    return result


def import_archive(data: bytes, root: Path) -> dict:
    if len(data) > MAX_BYTES or sha(data) != OUTER_SHA:
        raise ValueError('Source artifact SHA256 mismatch')
    with zipfile.ZipFile(io.BytesIO(data)) as outer:
        names = members(outer)
        if set(names) != {'archive-sha256.txt', 'combat-source.zip'}:
            raise ValueError('Unexpected outer artifact contents')
        raw = outer.read('combat-source.zip')
        if sha(raw) != outer.read('archive-sha256.txt').decode().strip():
            raise ValueError('Inner source archive SHA256 mismatch')
    prepared = []
    receipt = []
    with zipfile.ZipFile(io.BytesIO(raw)) as source:
        names = members(source)
        manifest_bytes = source.read('source-manifest.json')
        manifest = json.loads(manifest_bytes)
        if manifest.get('repository') != 'xlbaoxl/canghuo-game' or manifest.get('commit') != SOURCE:
            raise ValueError('Unexpected source repository or revision')
        rows = manifest['files']
        if len(rows) != 173 or len({r['path'] for r in rows}) != len(rows):
            raise ValueError('Source inventory count or uniqueness mismatch')
        if set(names) != {'source-manifest.json'} | {r['path'] for r in rows}:
            raise ValueError('Source inventory does not cover exactly the archive')
        for row in rows:
            name = row['path']
            if name in ['docs/新版战斗.md', 'docs/战斗升级策划.md']:
                destination = 'archive/legacy_design/e101fca/' + PurePosixPath(name).name
            elif name.startswith('modules/training-camp/'):
                destination = name
            else:
                raise ValueError('Out-of-scope source path')
            if any(part in ['.git', '.godot', 'builds', '.env'] for part in PurePosixPath(name).parts):
                raise ValueError('Generated or private environment path rejected')
            payload = source.read(name)
            blob = hashlib.sha1(b'blob ' + str(len(payload)).encode() + b'\0' + payload).hexdigest()
            if len(payload) != row['size'] or sha(payload) != row['sha256'] or blob != row['blob']:
                raise ValueError('Source hash or size mismatch: ' + name)
            if payload.startswith(b'version https://git-lfs.github.com/spec/v1'):
                raise ValueError('Unmaterialized LFS pointer: ' + name)
            target = root / destination
            if not target.resolve().is_relative_to(root) or target.is_symlink():
                raise ValueError('Unsafe destination')
            if target.exists() and (not target.is_file() or target.read_bytes() != payload):
                raise ValueError('Concurrent destination content: ' + destination)
            mode = (names[name].external_attr >> 16) & 0o777
            prepared.append((target, payload, 0o755 if mode & 0o111 else 0o644))
            receipt.append({**row, 'destination': destination})
    # Check all inputs and destinations before the first write.
    for target, payload, mode in prepared:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
        target.chmod(mode)
    record_dir = root / 'migration'
    record_dir.mkdir(parents=True, exist_ok=True)
    (record_dir / 'source_manifest_e101fca.json').write_bytes(manifest_bytes)
    report = {
        'status': 'PASS', 'source_repository': 'xlbaoxl/canghuo-game', 'source_commit': SOURCE,
        'source_export_run': 37821554938, 'source_artifact_sha256': OUTER_SHA,
        'source_manifest_sha256': sha(manifest_bytes), 'destination_repository': 'xlbaoxl/canghuo-combat',
        'module_files': sum(r['destination'].startswith('modules/') for r in receipt),
        'historical_design_files': sum(r['destination'].startswith('archive/') for r in receipt),
        'runtime_changed': False, 'engine_executed': False, 'files': receipt,
    }
    (record_dir / 'source_import_receipt.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--ticket', type=Path)
    parser.add_argument('--root', type=Path, default=Path.cwd())
    args = parser.parse_args()
    if bool(args.archive) == bool(args.ticket):
        parser.error('Provide exactly one of --archive and --ticket')
    try:
        if args.archive:
            payload = args.archive.read_bytes()
        else:
            ticket = json.loads(args.ticket.read_text(encoding='utf-8'))
            url = ticket['download_url']
            parsed = urllib.parse.urlsplit(url)
            if parsed.scheme != 'https' or not parsed.netloc.endswith('.oaiusercontent.com') or not parsed.path.startswith('/files/') or parsed.username:
                raise ValueError('Only the returned artifact download URL is accepted')
            if ticket.get('artifact_id') != 11568629691 or ticket.get('sha256') != OUTER_SHA:
                raise ValueError('Unapproved source ticket')
            if os.environ.get('GITHUB_ACTIONS') == 'true':
                print('::add-mask::' + url)
                print('::add-mask::' + parsed.query)
            with urllib.request.urlopen(url, timeout=60) as response:
                payload = response.read(MAX_BYTES + 1)
        report = import_archive(payload, args.root.resolve())
        print(json.dumps({k:v for k,v in report.items() if k != 'files'}, ensure_ascii=False, indent=2))
        return 0
    except Exception as exc:
        # A network exception can contain the capability URL; never print it.
        print('Source migration failed: '+type(exc).__name__, file=sys.stderr)
        if isinstance(exc, ValueError):
            print(str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
