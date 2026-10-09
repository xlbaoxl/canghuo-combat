#!/usr/bin/env python3
"""One-time private repository transfer; never accepts or exports an account token.
The transport is an expiring, file-specific GitHub artifact download link supplied
in the same-repository PR. No URL is saved in Git, receipts or diagnostic output.
All source bytes are verified before any destination is written.
"""
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit
import hashlib, io, json, os, re, stat, sys, urllib.error, urllib.request, zipfile

REPO = 'xlbaoxl/canghuo-combat'
BRANCH = 'chore/publish-combat-source-r4-20261009'
COMMIT = 'e101fca146bf340d8738dbaa3931c827e4efc227'
OUTER_SHA = '809a9a12d09dec39420329e4f21ee989ad2194c7c4c0f1181ba64ddd6b933455'
INNER_SHA = '3c6937b4ef35a839fd95a2b4c19ddc63ae85089782dd10d6d5a47c3add95a9d9'
ROOT = Path.cwd().resolve()

def sha(data):
    return hashlib.sha256(data).hexdigest()

def check_zip(z, maximum):
    infos = z.infolist()
    if len(infos) > 1000 or len(set(i.filename for i in infos)) != len(infos):
        raise ValueError('Duplicate or excessive archive entries')
    if sum(i.file_size for i in infos) > maximum:
        raise ValueError('Expanded archive exceeds declared scope')
    for i in infos:
        p = PurePosixPath(i.filename)
        if p.is_absolute() or '..' in p.parts or '\\' in i.filename or stat.S_ISLNK(i.external_attr >> 16):
            raise ValueError('Unsafe archive member')

def main():
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    pr = event.get('pull_request', {})
    if pr.get('head', {}).get('repo', {}).get('full_name') != REPO or pr.get('head', {}).get('ref') != BRANCH:
        raise ValueError('Unexpected pull-request origin')
    match = re.search(r'```combat-transfer\s*\n(\{.*?\})\s*\n```', pr.get('body') or '', re.S)
    if not match:
        print('No file transfer requested; no source writes performed.')
        return
    spec = json.loads(match.group(1))
    if spec.get('source_commit') != COMMIT or spec.get('artifact_id') != 11568629691:
        raise ValueError('Unexpected source identity')
    url = spec['download_url']
    u = urlsplit(url)
    host = (u.hostname or '').lower()
    if u.scheme != 'https' or u.username or u.password or not (host.endswith('.blob.core.windows.net') or host.endswith('.actions.githubusercontent.com') or host == 'results-receiver.actions.githubusercontent.com'):
        raise ValueError('Not a GitHub artifact storage endpoint')
    print('::add-mask::' + url)
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent':'canghuo-owner-authorized-artifact-transfer'}), timeout=90) as response:
            payload = response.read(80 * 1024 * 1024 + 1)
    except urllib.error.HTTPError as exc:
        raise ValueError('Artifact transport HTTP ' + str(exc.code)) from None
    except Exception:
        raise ValueError('Artifact transport failed; private URL omitted') from None
    if len(payload) > 80 * 1024 * 1024 or sha(payload) != OUTER_SHA:
        raise ValueError('Artifact byte fingerprint mismatch')
    with zipfile.ZipFile(io.BytesIO(payload)) as outer:
        check_zip(outer, 90 * 1024 * 1024)
        inner = outer.read('combat-source.zip')
    if sha(inner) != INNER_SHA:
        raise ValueError('Inner source fingerprint mismatch')
    prepared = []
    with zipfile.ZipFile(io.BytesIO(inner)) as source:
        check_zip(source, 100 * 1024 * 1024)
        manifest = json.loads(source.read('source-manifest.json'))
        if manifest.get('repository') != 'xlbaoxl/canghuo-game' or manifest.get('commit') != COMMIT or len(manifest['files']) != 173:
            raise ValueError('Source manifest mismatch')
        names = set()
        for row in manifest['files']:
            name = row['path']
            if name in names:
                raise ValueError('Duplicate source path')
            names.add(name)
            p = PurePosixPath(name)
            if p.is_absolute() or '..' in p.parts or '\\' in name:
                raise ValueError('Invalid source path')
            if name.startswith('modules/training-camp/'):
                destination = name
            elif name in ('docs/新版战斗.md', 'docs/战斗升级策划.md'):
                destination = 'archive/game-e101fca/docs/' + p.name
            else:
                raise ValueError('Source outside approved combat scope')
            body = source.read(name)
            blob = hashlib.sha1(b'blob ' + str(len(body)).encode() + b'\0' + body).hexdigest()
            if len(body) != row['size'] or sha(body) != row['sha256'] or blob != row['blob']:
                raise ValueError('Source member fingerprint mismatch: ' + name)
            if body.startswith(b'version https://git-lfs.github.com/spec/'):
                raise ValueError('Source is an LFS pointer, not actual content')
            target = ROOT / destination
            if not target.resolve().is_relative_to(ROOT) or any(x.is_symlink() for x in [target, *target.parents] if x != ROOT):
                raise ValueError('Unsafe destination')
            if target.exists() and (not target.is_file() or target.read_bytes() != body):
                raise ValueError('Refusing to replace different existing source: ' + destination)
            prepared.append((target, body, dict(row, destination=destination)))
        if set(source.namelist()) != names | {'source-manifest.json'}:
            raise ValueError('Unexpected unmanifested source members')
    for target, body, _ in prepared:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(body)
    receipt = {
        'format': 1, 'source_repository':'xlbaoxl/canghuo-game', 'source_commit':COMMIT,
        'source_export_run':37821554938, 'source_artifact_id':11568629691,
        'source_archive_sha256':INNER_SHA, 'artifact_sha256':OUTER_SHA,
        'scope':'Exact source and user-owned project assets transferred to the designated private combat repository; no game-rule changes',
        'module_files':171, 'historical_design_files':2, 'files':[row for _,_,row in prepared],
        'git_history_imported':False, 'source_modes_verified':False,
        'runtime_executed_by_importer':False
    }
    dest = ROOT / 'migration/source_manifest.json'
    dest.parent.mkdir(exist_ok=True)
    dest.write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write('imported=true\n')
    print('Verified and wrote 171 combat files and two historical design files. No account credentials transferred.')

if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, zipfile.BadZipFile) as exc:
        print('Import stopped: ' + str(exc))
        sys.exit(1)
