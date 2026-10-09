#!/usr/bin/env python3
"""Read-only archive integrity checks. PASS does not mean migration is complete.
--require-complete additionally rejects declared missing members/artifacts/source.
Never downloads files, executes archived scripts, or runs the combat engine.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlsplit

REQUIRED = [
    'README.md', 'AGENTS.md', 'docs/战斗设计总纲.md',
    'docs/战斗结算内核.md', 'docs/阵法技能.md',
    'docs/讨论共识与演变.md', 'docs/实施状态与迁移清单.md',
    'research/来源与文件成果索引.md', 'migration/artifact_inventory.json',
]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def safe_path(root: Path, name: str) -> Path:
    p = PurePosixPath(name)
    if not name or p.is_absolute() or '..' in p.parts or '\\' in name or ':' in name:
        raise ValueError('Unsafe repository path: ' + name)
    target = root / name
    if not target.resolve().is_relative_to(root):
        raise ValueError('Path escapes repository: ' + name)
    for parent in [target, *target.parents]:
        if parent == root:
            break
        if parent.is_symlink():
            raise ValueError('Symlink is not an archived regular file: ' + name)
    return target


def transformed(raw: bytes, mode: str) -> bytes:
    if mode == 'identity':
        return raw
    if mode == 'crlf_to_lf':
        return raw.replace(b'\r\n', b'\n')
    raise ValueError('Unsupported declared transformation: ' + mode)


def validate(root: Path, artifacts: Path | None = None,
             require_complete: bool = False) -> dict:
    root = root.resolve()
    errors: list[str] = []
    checks = 0
    def check(ok: bool, message: str) -> None:
        nonlocal checks
        checks += 1
        if not ok:
            errors.append(message)
    def fingerprint(path: Path, size: int, digest: str) -> bool:
        return path.is_file() and path.stat().st_size == size and sha256(path) == digest
    for name in REQUIRED:
        check(safe_path(root, name).is_file(), 'Missing required file: ' + name)
    manifest = json.loads((root / 'migration/artifact_inventory.json').read_text(encoding='utf-8'))
    check(manifest.get('authoritative_repository') == 'xlbaoxl/canghuo-combat', 'Wrong repository authority')
    original_checks = []
    pending_artifacts = []
    names = set()
    for item in manifest['artifacts']:
        name = item['name']
        check(name not in names and PurePosixPath(name).name == name, 'Duplicate/invalid artifact basename: ' + name)
        safe_path(root, name)
        names.add(name)
        check(bool(re.fullmatch(r'[0-9a-f]{64}', item.get('sha256', ''))), 'Invalid SHA256: ' + name)
        destination = item.get('repository_copy', 'pending')
        if destination.startswith('pending'):
            pending_artifacts.append(name)
        else:
            check(fingerprint(safe_path(root, destination), item['bytes'], item['sha256']), 'Archived artifact hash/size mismatch: ' + name)
        if artifacts is not None:
            passed = fingerprint(safe_path(artifacts.resolve(), name), item['bytes'], item['sha256'])
            check(passed, 'Original artifact missing or hash/size mismatch: ' + name)
            original_checks.append({'name': name, 'matched': passed})

    member_path = root / 'migration/research_members.json'
    packages = json.loads(member_path.read_text(encoding='utf-8')).get('packages', []) if member_path.is_file() else []
    members = {}
    pending_members = []
    archived_members = []
    for package in packages:
        archive_root = package['archive_root']
        check(archive_root.startswith('research/originals/'), 'Unexpected original archive root')
        safe_path(root, archive_root)
        check(package['total_members'] == len(package['members']), 'Incorrect member count: ' + archive_root)
        source_file = safe_path(artifacts.resolve(), package['source_artifact']) if artifacts else None
        source_zip = zipfile.ZipFile(source_file) if source_file and source_file.suffix == '.zip' and source_file.is_file() else None
        try:
            for row in package['members']:
                dest = row['destination']
                check(dest == archive_root + '/' + row['member'], 'Member mapping mismatch: ' + dest)
                check(dest not in members, 'Duplicate member destination: ' + dest)
                target = safe_path(root, dest)
                members[dest] = dict(row, package=archive_root)
                check(bool(re.fullmatch(r'[0-9a-f]{64}', row.get('source_sha256', ''))), 'Invalid member SHA256: ' + dest)
                if row['status'] == 'archived':
                    check(fingerprint(target, row['archived_bytes'], row['archived_sha256']), 'Archived member missing or altered: ' + dest)
                    mode = row.get('transform', 'identity')
                    check(mode in ['identity', 'crlf_to_lf'], 'Unknown member transformation: ' + dest)
                    if mode == 'identity':
                        check(row['archived_bytes'] == row['source_bytes'] and row['archived_sha256'] == row['source_sha256'], 'Identity claim does not match original: ' + dest)
                    archived_members.append(dest)
                elif row['status'] == 'pending':
                    check(not target.exists(), 'Pending member unexpectedly exists; update receipt: ' + dest)
                    pending_members.append(dest)
                else:
                    check(False, 'Invalid member status: ' + dest)
                if source_file:
                    raw = source_zip.read(package['source_prefix'] + row['member']) if source_zip else source_file.read_bytes()
                    check(len(raw) == row['source_bytes'] and hashlib.sha256(raw).hexdigest() == row['source_sha256'], 'Original member mismatch: ' + dest)
                    if row['status'] == 'archived':
                        check(target.read_bytes() == transformed(raw, row.get('transform', 'identity')), 'Archive differs from declared source transformation: ' + dest)
        finally:
            if source_zip:
                source_zip.close()

    links = 0
    deferred = []
    for path in sorted(root.rglob('*.md')):
        if '.git' in path.parts:
            continue
        rel = path.relative_to(root).as_posix()
        text = path.read_text(encoding='utf-8')
        check(sum(line.lstrip().startswith('```') for line in text.splitlines()) % 2 == 0, 'Unbalanced fenced block: ' + rel)
        for destination in re.findall(r'\]\(([^)]+)\)', text):
            if urlsplit(destination).scheme or destination.startswith('#'):
                continue
            name = unquote(destination.split('#', 1)[0])
            if not name:
                continue
            target = (path.parent / name).resolve()
            links += 1
            if not target.is_relative_to(root):
                check(False, 'Link escapes repository: ' + rel + ' -> ' + destination)
                continue
            target_rel = target.relative_to(root).as_posix()
            source_member = members.get(rel, {})
            target_member = members.get(target_rel, {})
            # Only an unchanged historical source may point to an explicitly
            # inventoried pending member of that very same original package.
            if not target.exists() and source_member.get('status') == 'archived' and target_member.get('status') == 'pending' and source_member.get('package') == target_member.get('package'):
                deferred.append({'source': rel, 'destination': target_rel})
                check(True, '')
            else:
                check(target.exists(), 'Broken local link: ' + rel + ' -> ' + destination)

    source_receipt = root / 'migration/source_manifest.json'
    source_verified = False
    if source_receipt.is_file():
        source = json.loads(source_receipt.read_text(encoding='utf-8'))
        start = len(errors)
        check(source.get('source_commit') == 'e101fca146bf340d8738dbaa3931c827e4efc227', 'Wrong source import baseline')
        for row in source.get('files', []):
            check(fingerprint(safe_path(root, row['destination']), row['size'], row['sha256']), 'Imported source mismatch: ' + row['destination'])
        check(len(source.get('files', [])) == 173, 'Incomplete original source manifest')
        source_verified = len(errors) == start
    complete = not pending_artifacts and not pending_members and not manifest.get('unlocated_originals') and source_verified
    if require_complete:
        check(complete, 'Migration is incomplete: declared missing artifacts/members/originals or unverified source')
    return {
        'status': 'FAIL' if errors else 'PASS',
        'scope': 'Archive integrity only; declared historical gaps are listed, not counted as completed migration',
        'checks': checks, 'relative_links_checked': links,
        'original_artifacts_checked': original_checks,
        'archived_members_checked': archived_members,
        'pending_research_members': pending_members,
        'deferred_historical_links': deferred,
        'pending_repository_artifact_copies': pending_artifacts,
        'unlocated_originals': manifest.get('unlocated_originals', []),
        'migration_complete': complete, 'require_complete': require_complete,
        'engine_project_present': (root / 'modules/training-camp/project/project.godot').is_file(),
        'source_copy_verified': source_verified,
        'gameplay_or_godot_executed': False,
        'errors': errors,
    }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    p.add_argument('--artifacts-dir', type=Path)
    p.add_argument('--require-complete', action='store_true')
    p.add_argument('--output', type=Path)
    args = p.parse_args()
    try:
        result = validate(args.root, args.artifacts_dir, args.require_complete)
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as e:
        result = {'status': 'FAIL', 'scope': 'archive integrity', 'migration_complete': False, 'gameplay_or_godot_executed': False, 'errors': [str(e)]}
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    print(text, end='')
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
    return 1 if result['status'] == 'FAIL' else 0

if __name__ == '__main__':
    raise SystemExit(main())
