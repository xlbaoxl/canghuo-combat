#!/usr/bin/env python3
"""Copy a verified main-branch Web release to a dedicated, private Git branch.
No Vercel credentials, hosting API calls, source publishing, or force pushes.
The owner must connect this branch and configure access in Vercel's website.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import urllib.error
import urllib.request

from deploy_vercel import NoRedirect, verified_files

REPOSITORY = 'xlbaoxl/canghuo-combat'
SITE_BRANCH = 'web-playtest-site'
MARKER = {'schema': 1, 'kind': 'verified-web-runtime-branch', 'repository': REPOSITORY}
WORKFLOW_PATH = '.github/workflows/web-playtest.yml'


def eligible_run(run: dict, current_sha: str) -> bool:
    """Reject PR/fork/other-workflow artifacts; obsolete successful runs are skipped."""
    if not re.fullmatch(r'[0-9a-f]{40}', current_sha):
        raise ValueError('Expected an exact current main commit')
    if (run.get('repository', {}).get('full_name') != REPOSITORY
            or run.get('repository', {}).get('private') is not True
            or run.get('head_repository', {}).get('full_name') != REPOSITORY
            or run.get('head_branch') != 'main'
            or run.get('event') not in {'push', 'workflow_dispatch'}
            or run.get('path') != WORKFLOW_PATH
            or run.get('status') != 'completed'
            or run.get('conclusion') != 'success'):
        raise ValueError('Only successful trusted main Web workflows may update the site branch')
    return run.get('head_sha') == current_sha


def github_get(path: str) -> dict:
    if not path.startswith('/repos/' + REPOSITORY + '/') or '?' in path or '..' in path:
        raise ValueError('Unexpected GitHub API path')
    token = os.environ.get('GH_TOKEN', '')
    if not token:
        raise ValueError('This operation needs the workflow GITHUB_TOKEN, not a Vercel token')
    request = urllib.request.Request('https://api.github.com' + path, headers={
        'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'canghuo-web-site-sync'})
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f'GitHub read returned HTTP {error.code}; nothing published') from None


def inspect_run(run_id: int) -> dict:
    if run_id <= 0:
        raise ValueError('A positive Web workflow run ID is required')
    prefix = '/repos/' + REPOSITORY
    run = github_get(prefix + '/actions/runs/' + str(run_id))
    current = github_get(prefix + '/git/ref/heads/main')['object']['sha']
    return {'eligible': eligible_run(run, current), 'commit': run['head_sha'], 'run_id': run_id}


def allowed_file(name: str) -> bool:
    if name in {'vercel.json', 'site-branch.json'}:
        return True
    if not name.startswith('public/'):
        return False
    name = name[len('public/'):]
    return name in {'build.json', 'robots.txt'} or bool(re.fullmatch(
        r'index(?:\.[a-z0-9_-]+)*\.(?:html|js|wasm|pck|png)', name))


def inspect_tree(root: Path) -> list[Path]:
    if root.is_symlink() or not root.is_dir():
        raise ValueError('Expected a real site directory')
    marker_path = root / 'site-branch.json'
    if marker_path.is_symlink() or not marker_path.is_file():
        raise ValueError('Refusing a branch without the dedicated site marker')
    marker = json.loads(marker_path.read_text(encoding='utf-8'))
    if any(marker.get(key) != value for key, value in MARKER.items()):
        raise ValueError('Refusing to replace another branch or repository')
    files = []
    for path in root.rglob('*'):
        relative = path.relative_to(root).as_posix()
        if relative == '.git' or relative.startswith('.git/'):
            continue
        if path.is_symlink():
            raise ValueError('Site branch may not contain symlinks')
        if path.is_dir():
            if relative != 'public':
                raise ValueError('Unexpected site directory: ' + relative)
            continue
        if not path.is_file() or not allowed_file(relative):
            raise ValueError('Refusing to overwrite unexpected site content: ' + relative)
        files.append(path)
    if not (root / 'public/index.html').is_file() or not (root / 'vercel.json').is_file():
        raise ValueError('Site branch is incomplete')
    return files


def prepare(release: Path, evidence: Path, commit: str, run_id: int, output: Path) -> dict:
    if output.exists() or output.is_symlink():
        raise ValueError('Use a new package directory')
    if run_id <= 0:
        raise ValueError('A source workflow run ID is required')
    browser_path = evidence / 'web-browser-evidence/browser-checks.json'
    build_path = evidence / 'web-release-evidence/build-result.json'
    meta, files = verified_files(release, browser_path, build_path, commit)
    build = json.loads(build_path.read_text(encoding='utf-8'))
    browser = json.loads(browser_path.read_text(encoding='utf-8'))
    # Bind not only the commit but the exact generated files and build identity.
    if build.get('build') != meta or any(meta.get(k) != v for k, v in browser['build'].items()):
        raise ValueError('Build artifacts differ from the verified build manifest')
    config = json.loads(files.pop('vercel.json'))
    config['outputDirectory'] = 'public'
    payload = {'public/' + name: data for name, data in files.items()}
    payload['vercel.json'] = (json.dumps(config, indent=2) + '\n').encode()
    marker = {**MARKER, 'source_commit': commit, 'source_run_id': run_id,
              'hosting_verified': False, 'files': {
                  name: hashlib.sha256(data).hexdigest() for name, data in sorted(payload.items())}}
    payload['site-branch.json'] = (json.dumps(marker, indent=2) + '\n').encode()
    if not all(allowed_file(name) for name in payload):
        raise ValueError('Non-runtime content in generated package')
    (output / 'public').mkdir(parents=True)
    for name, data in payload.items():
        (output / name).write_bytes(data)
    inspect_tree(output)
    return {'source_commit': commit, 'source_run_id': run_id,
            'file_count': len(payload), 'bytes': sum(map(len, payload.values())),
            'branch': SITE_BRANCH, 'hosting_verified': False}


def replace_site(package: Path, target: Path) -> None:
    if package.resolve() == target.resolve() or package.resolve().is_relative_to(target.resolve()) or target.resolve().is_relative_to(package.resolve()):
        raise ValueError('Package and target must be independent directories')
    new_files, old_files = inspect_tree(package), inspect_tree(target)
    # Validate everything before removing any generated file. Git history is retained.
    marker = json.loads((package / 'site-branch.json').read_text())
    hashes = marker.get('files', {})
    names = {p.relative_to(package).as_posix() for p in new_files} - {'site-branch.json'}
    if names != set(hashes) or any(hashlib.sha256((package / n).read_bytes()).hexdigest() != h for n, h in hashes.items()):
        raise ValueError('Generated package fingerprint changed')
    for path in old_files:
        path.unlink()
    for path in new_files:
        destination = target / path.relative_to(package)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    inspect = commands.add_parser('inspect-run')
    inspect.add_argument('--run-id', required=True, type=int)
    package = commands.add_parser('prepare')
    for name in ('release', 'evidence', 'output'):
        package.add_argument('--' + name, required=True, type=Path)
    package.add_argument('--commit', required=True)
    package.add_argument('--run-id', required=True, type=int)
    apply = commands.add_parser('replace')
    apply.add_argument('--package', required=True, type=Path)
    apply.add_argument('--target', required=True, type=Path)
    args = parser.parse_args()
    if args.command == 'inspect-run':
        result = inspect_run(args.run_id)
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as out:
                for key, value in result.items():
                    out.write(f'{key}={str(value).lower() if isinstance(value, bool) else value}\n')
    elif args.command == 'prepare':
        result = prepare(args.release, args.evidence, args.commit, args.run_id, args.output)
    else:
        replace_site(args.package, args.target)
        result = {'worktree_prepared': True, 'git_pushed': False, 'hosting_verified': False}
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    main()
