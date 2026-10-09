#!/usr/bin/env python3
"""Apply a fingerprinted combat migration bundle to a clean, authenticated local clone.
Default: validate only. --write copies reviewed files. --publish additionally creates
an isolated branch, commits, pushes without force and opens a PR using existing git/gh
authentication. Never requests, reads, prints or stores an access token.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

REPOSITORY = 'xlbaoxl/canghuo-combat'
MAX_FILE = 96 * 1024 * 1024
MAX_TOTAL = 512 * 1024 * 1024
SOURCE_REPOSITORY = 'xlbaoxl/canghuo-game'
SOURCE_COMMIT = 'e101fca146bf340d8738dbaa3931c827e4efc227'


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_target(root: Path, name: str) -> Path:
    p = PurePosixPath(name)
    if not name or name != p.as_posix() or p.is_absolute() or any(x in ('..', '.git') for x in p.parts) or '\\' in name or ':' in name:
        raise ValueError('Unsafe path: ' + name)
    target = root / name
    if not target.resolve().is_relative_to(root):
        raise ValueError('Path escapes destination: ' + name)
    for parent in [target, *target.parents]:
        if parent == root:
            break
        if parent.is_symlink():
            raise ValueError('Refusing symlink destination: ' + name)
    return target


def prepare(bundle: Path, root: Path, source_repo: Path | None = None) -> tuple[dict, list[tuple[Path, bytes, str]]]:
    """Read every entry and check every precondition before any write."""
    with zipfile.ZipFile(bundle) as z:
        infos = z.infolist()
        if len(infos) > 1000 or len({i.filename for i in infos}) != len(infos):
            raise ValueError('Duplicate or excessive ZIP entries')
        if sum(i.file_size for i in infos) > MAX_TOTAL:
            raise ValueError('Expanded bundle too large')
        if any(i.file_size > MAX_FILE or stat.S_ISLNK(i.external_attr >> 16) for i in infos):
            raise ValueError('Oversized file or symlink in ZIP')
        manifest = json.loads(z.read('migration-bundle.json'))
        if manifest.get('format') != 1 or manifest.get('repository') != REPOSITORY:
            raise ValueError('Wrong bundle format or repository')
        rows = manifest['files']
        names = [r['path'] for r in rows]
        if len(set(names)) != len(names):
            raise ValueError('Duplicate destination')
        if len(rows) > 1000 or sum(int(r['size']) for r in rows) > MAX_TOTAL:
            raise ValueError('Expanded manifest too large')
        expected = {'migration-bundle.json', 'README.txt'} | {
            'payload/' + r['path'] for r in rows if r.get('storage', 'payload') == 'payload'
        }
        if {i.filename for i in infos if not i.is_dir()} != expected:
            raise ValueError('Unmanifested or missing bundle member')
        prepared = []
        for row in rows:
            name = row['path']
            target = safe_target(root, name)
            storage = row.get('storage', 'payload')
            if storage == 'payload':
                data = z.read('payload/' + name)
            elif storage == 'local_source':
                if row.get('source_commit') != SOURCE_COMMIT or row.get('source_path') != name or not name.startswith('modules/training-camp/'):
                    raise ValueError('Invalid original source dependency: ' + name)
                if target.is_file() and digest(target.read_bytes()) == row['sha256']:
                    data = target.read_bytes()
                else:
                    if source_repo is None:
                        raise ValueError('Original project dependency requires --source-repo pointing to the existing local canghuo-game clone: ' + name)
                    remote = command(['git', 'remote', 'get-url', 'origin'], source_repo, True)
                    if remote not in {f'https://github.com/{SOURCE_REPOSITORY}', f'https://github.com/{SOURCE_REPOSITORY}.git', f'git@github.com:{SOURCE_REPOSITORY}.git', f'ssh://git@github.com/{SOURCE_REPOSITORY}.git'}:
                        raise ValueError('Original source repository does not match')
                    data = subprocess.run(['git', 'show', SOURCE_COMMIT + ':' + name], cwd=source_repo, check=True, stdout=subprocess.PIPE).stdout
            else:
                raise ValueError('Unknown storage kind: ' + storage)
            if len(data) != row['size'] or digest(data) != row['sha256']:
                raise ValueError('Payload fingerprint mismatch: ' + name)
            if row.get('mode', '100644') not in ('100644', '100755'):
                raise ValueError('Unsupported file mode: ' + name)
            if target.exists():
                if not target.is_file():
                    raise ValueError('Destination is not a regular file: ' + name)
                actual = digest(target.read_bytes())
                if actual not in [row['sha256'], row.get('base_sha256')]:
                    raise ValueError('Concurrent/local content differs; reconcile before applying: ' + name)
            elif row.get('base_sha256') is not None:
                raise ValueError('Expected base file is missing: ' + name)
            prepared.append((target, data, row.get('mode', '100644')))
    return manifest, prepared


def command(args: list[str], cwd: Path, capture: bool = False) -> str:
    result = subprocess.run(args, cwd=cwd, check=True, text=True, encoding='utf-8', errors='replace',
                            stdout=subprocess.PIPE if capture else None)
    return (result.stdout or '').strip()


def check_clone(root: Path) -> None:
    top = Path(command(['git', 'rev-parse', '--show-toplevel'], root, True)).resolve()
    if top != root:
        raise ValueError('--repo must be the repository root')
    remote = command(['git', 'remote', 'get-url', 'origin'], root, True)
    allowed = {f'https://github.com/{REPOSITORY}', f'https://github.com/{REPOSITORY}.git',
               f'git@github.com:{REPOSITORY}.git', f'ssh://git@github.com/{REPOSITORY}.git'}
    if remote not in allowed:
        raise ValueError('Origin is not the designated combat repository')
    if command(['git', 'status', '--porcelain', '--untracked-files=all'], root, True):
        raise ValueError('Worktree is not clean; keep the bundle outside the clone')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--source-repo', type=Path, help='Optional existing local original repository for manifest-declared original project dependencies')
    parser.add_argument('--write', action='store_true')
    parser.add_argument('--publish', action='store_true')
    parser.add_argument('--branch', default='chore/import-combat-complete-r3-20261009')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    root = args.repo.resolve()
    report = {'status': 'STARTED', 'repository': REPOSITORY, 'files_written': 0,
              'remote_pushed': False, 'pr_created': False, 'merged': False,
              'engine_executed_by_this_script': False}
    try:
        if args.publish and not args.write:
            raise ValueError('--publish requires --write')
        if not re.fullmatch(r'[A-Za-z0-9_./-]+', args.branch) or '..' in args.branch or args.branch == 'main':
            raise ValueError('Use a separate ordinary branch')
        check_clone(root)
        manifest, prepared = prepare(args.bundle.resolve(), root, args.source_repo.resolve() if args.source_repo else None)
        report.update(bundle_sha256=digest(args.bundle.read_bytes()), files=len(prepared),
                      source_commit=manifest['source_commit'])
        if args.publish:
            if shutil.which('gh') is None:
                raise ValueError('GitHub CLI gh is required for --publish; use an existing local login')
            command(['gh', 'auth', 'status', '--hostname', 'github.com'], root)
            command(['git', 'fetch', 'origin', 'main'], root)
            current = command(['git', 'rev-parse', 'HEAD'], root, True)
            latest = command(['git', 'rev-parse', 'origin/main'], root, True)
            if current != latest:
                raise ValueError('Local HEAD is not current origin/main; update/reconcile, then retry')
            command(['git', 'check-ref-format', '--branch', args.branch], root)
            command(['git', 'switch', '-c', args.branch], root)
            report['base_commit'] = current
        if not args.write:
            report['status'] = 'VERIFIED_DRY_RUN'
        else:
            for target, data, mode in prepared:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                if os.name != 'nt':
                    target.chmod(0o755 if mode == '100755' else 0o644)
                report['files_written'] += 1
            # Explicit --write authorizes the reviewed archive validators, not a game build.
            command([sys.executable, 'tools/validate_archive.py', '--root', str(root)], root)
            command([sys.executable, '-m', 'unittest', 'discover', '-s', 'tools/tests', '-v'], root)
            report['status'] = 'APPLIED_AND_CHECKED_LOCALLY'
        if args.publish:
            with tempfile.NamedTemporaryFile('wb', delete=False) as handle:
                pathspec = Path(handle.name)
                handle.write(b'\0'.join(r['path'].encode('utf-8') for r in manifest['files']) + b'\0')
            try:
                command(['git', 'add', '--pathspec-from-file=' + str(pathspec), '--pathspec-file-nul'], root)
            finally:
                pathspec.unlink(missing_ok=True)
            command(['git', '-c', 'core.quotepath=false', 'diff', '--cached', '--stat'], root)
            command(['git', 'commit', '-m', 'chore: import verified combat 3.0.1 module and research originals'], root)
            report['commit'] = command(['git', 'rev-parse', 'HEAD'], root, True)
            command(['git', 'push', '-u', 'origin', 'HEAD:refs/heads/' + args.branch], root)
            report['remote_pushed'] = True
            body = ('Import the fingerprinted local migration bundle. No combat-rule, content or asset changes. '
                    'Preserve original source and research evidence; run archive checks. '
                    'Local preparation and engine verification are recorded separately from CI and author playtests. '
                    'Early unlocated originals remain explicitly listed. Do not auto-merge before reviewing checks.')
            report['pr_url'] = command(['gh', 'pr', 'create', '--repo', REPOSITORY, '--base', 'main',
                                       '--head', args.branch, '--title', 'chore: complete combat source and known artifact migration',
                                       '--body', body], root, True)
            report['pr_created'] = True
            report['status'] = 'PUSHED_PR_OPEN'
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile, subprocess.CalledProcessError) as exc:
        report.update(status='FAILED', error=str(exc), exception=type(exc).__name__)
        if report['files_written']:
            report['recovery'] = 'Files may remain locally; inspect the worktree. No rollback, reset, force push or deletion was performed.'
    output = json.dumps(report, ensure_ascii=False, indent=2) + '\n'
    print(output, end='')
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output, encoding='utf-8')
    return 1 if report['status'] == 'FAILED' else 0

if __name__ == '__main__':
    raise SystemExit(main())
