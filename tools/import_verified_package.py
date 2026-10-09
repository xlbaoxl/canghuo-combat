#!/usr/bin/env python3
"""Import only the pinned research ZIP or pinned 3.0.1 source export.
Default is a dry-run. Supply --write in a reviewed repository worktree to copy.
No network, gameplay execution, git commit, push, or source deletion is performed.
All payloads and existing destinations are checked before writes start.
"""
from __future__ import annotations
import argparse
import hashlib
import io
import json
import stat
import zipfile
from pathlib import Path
from validate_archive import safe_path

SOURCE_COMMIT = 'e101fca146bf340d8738dbaa3931c827e4efc227'
SOURCE_ZIP = '3c6937b4ef35a839fd95a2b4c19ddc63ae85089782dd10d6d5a47c3add95a9d9'
SOURCE_ARTIFACT = '809a9a12d09dec39420329e4f21ee989ad2194c7c4c0f1181ba64ddd6b933455'
RESEARCH_ZIP = '1eba3070b3d36c4f0009a7d7d94ba50687f6db448ac5a795ae37fc3c716363a1'


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def archive(data: bytes) -> zipfile.ZipFile:
    z = zipfile.ZipFile(io.BytesIO(data))
    infos = z.infolist()
    if len({i.filename for i in infos}) != len(infos):
        raise ValueError('Duplicate ZIP entries')
    if sum(i.file_size for i in infos) > 100 * 1024 * 1024:
        raise ValueError('Unexpected expanded archive size')
    if any(stat.S_ISLNK(i.external_attr >> 16) for i in infos):
        raise ValueError('Symlinks not accepted')
    return z


def prepare(root: Path, kind: str, data: bytes) -> tuple[dict[str, bytes], dict]:
    files: dict[str, bytes] = {}
    metadata: dict = {}
    if kind == 'module':
        if digest(data) == SOURCE_ARTIFACT:
            with archive(data) as outer:
                data = outer.read('combat-source.zip')
        if digest(data) != SOURCE_ZIP:
            raise ValueError('Not the pinned combat source archive')
        with archive(data) as z:
            source = json.loads(z.read('source-manifest.json'))
            if source['repository'] != 'xlbaoxl/canghuo-game' or source['commit'] != SOURCE_COMMIT or len(source['files']) != 173:
                raise ValueError('Wrong module manifest identity')
            rows = []
            for row in source['files']:
                name = row['path']
                safe_path(root, name)
                raw = z.read(name)
                blob = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
                if len(raw) != row['size'] or digest(raw) != row['sha256'] or blob != row['blob']:
                    raise ValueError('Source member mismatch: ' + name)
                if raw.startswith(b'version https://git-lfs.github.com/spec/'):
                    raise ValueError('LFS pointer instead of source bytes: ' + name)
                if name.startswith('modules/training-camp/'):
                    dest = name
                elif name in ['docs/新版战斗.md', 'docs/战斗升级策划.md']:
                    dest = 'archive/game-e101fca/' + name
                else:
                    raise ValueError('Out-of-scope source: ' + name)
                if dest in files:
                    raise ValueError('Duplicate source destination')
                files[dest] = raw
                rows.append(dict(row, destination=dest))
        metadata = {'format':1, 'source_repository':'xlbaoxl/canghuo-game', 'source_commit':SOURCE_COMMIT,
                    'source_export_run':37821554938, 'source_archive_sha256':SOURCE_ZIP,
                    'module_files':171, 'historical_design_files':2, 'files':rows,
                    'git_history_imported':False, 'source_git_modes_captured':False,
                    'runtime_executed_by_importer':False,
                    'scope':'Pinned source bytes only; original export did not capture Git modes; review paths and run new-repository tests separately'}
        files['migration/source_manifest.json'] = (json.dumps(metadata, ensure_ascii=False, indent=2)+'\n').encode()
    else:
        if digest(data) != RESEARCH_ZIP:
            raise ValueError('Not the pinned R4 research ZIP')
        path = root / 'migration/research_members.json'
        document = json.loads(path.read_text(encoding='utf-8'))
        package = next(p for p in document['packages'] if p['source_artifact'] == 'combat_research_20260930_R4_final.zip')
        if package['archive_root'] != 'research/originals/combat_research_20260930_R4_final' or package['source_prefix'] != 'combat_research_20260930_R4_final/':
            raise ValueError('Research archive root cannot be remapped')
        if package['total_members'] != 36 or len(package['members']) != 36:
            raise ValueError('Incomplete research member registry')
        with archive(data) as z:
            actual = {i.filename for i in z.infolist() if not i.is_dir()}
            expected = {package['source_prefix'] + row['member'] for row in package['members']}
            if actual != expected:
                raise ValueError('Research member set mismatch')
            for row in package['members']:
                dest = row['destination']
                if dest != package['archive_root'] + '/' + row['member']:
                    raise ValueError('Research destination mapping mismatch')
                raw = z.read(package['source_prefix'] + row['member'])
                if len(raw) != row['source_bytes'] or digest(raw) != row['source_sha256']:
                    raise ValueError('Research original mismatch: ' + dest)
                files[dest] = raw
                row.update(status='archived', transform='identity', archived_bytes=len(raw), archived_sha256=digest(raw))
        # The caller explicitly authorizes this metadata transition after a full copy.
        files['migration/research_members.json'] = (json.dumps(document, ensure_ascii=False, indent=2)+'\n').encode()
        metadata = {'source_archive_sha256':RESEARCH_ZIP, 'members':36, 'original_zip_copied':False,
                    'scope':'Extracted originals; ZIP/release inventory and narrative state require a separate reviewed update'}
    return files, metadata


def import_package(root: Path, kind: str, source: Path, write: bool = False) -> dict:
    root = root.resolve()
    if source.stat().st_size > 80 * 1024 * 1024:
        raise ValueError('Input exceeds pinned package limit')
    files, details = prepare(root, kind, source.read_bytes())
    prepared = []
    for name, data in files.items():
        path = safe_path(root, name)
        if path.exists() and path.read_bytes() != data:
            if not (kind == 'research' and name == 'migration/research_members.json'):
                raise ValueError('Refusing different existing destination: ' + name)
        prepared.append((path, data))
    # This does not claim a filesystem-wide atomic transaction. A write failure
    # must be reported and rechecked; --write is normally used on a clean branch.
    if write:
        for path, data in prepared:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    return {'status':'IMPORTED' if write else 'VERIFIED_DRY_RUN', 'kind':kind,
            'files':len(prepared), 'bytes':sum(len(b) for _, b in prepared),
            'source_unchanged':True, 'git_commit_or_push_performed':False,
            'gameplay_or_godot_executed':False, 'details':details}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--kind', choices=['research', 'module'], required=True)
    p.add_argument('--input', type=Path, required=True)
    p.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    p.add_argument('--write', action='store_true')
    p.add_argument('--output', type=Path)
    args = p.parse_args()
    try:
        result = import_package(args.root, args.kind, args.input, args.write)
    except (OSError, ValueError, KeyError, StopIteration, TypeError, zipfile.BadZipFile) as e:
        result = {'status':'FAIL', 'error':str(e), 'gameplay_or_godot_executed':False}
    text = json.dumps(result, ensure_ascii=False, indent=2)+'\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
    print(text, end='')
    return 1 if result['status'] == 'FAIL' else 0

if __name__ == '__main__':
    raise SystemExit(main())
