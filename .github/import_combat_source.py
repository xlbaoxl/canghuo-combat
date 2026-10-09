"""One-time import of the user's pinned private combat module. No gameplay changes."""
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit
import hashlib, io, json, os, stat, urllib.request, zipfile

ROOT = Path.cwd().resolve()
ticket = json.loads((ROOT / '.github/combat-source-ticket.json').read_text())
url = ticket['url']
assert urlsplit(url).scheme == 'https' and urlsplit(url).hostname.endswith('.oaiusercontent.com')
print('::add-mask::' + url)
# This short-lived URL authorizes this exact archive only. Never copy it to provenance.
with urllib.request.urlopen(url, timeout=120) as response:
    payload = response.read(80 * 1024 * 1024 + 1)
assert len(payload) <= 80 * 1024 * 1024
assert hashlib.sha256(payload).hexdigest() == ticket['artifact_sha256']
with zipfile.ZipFile(io.BytesIO(payload)) as outer:
    inner = outer.read('combat-source.zip')
assert hashlib.sha256(inner).hexdigest() == '3c6937b4ef35a839fd95a2b4c19ddc63ae85089782dd10d6d5a47c3add95a9d9'
prepared = []
with zipfile.ZipFile(io.BytesIO(inner)) as source:
    manifest = json.loads(source.read('source-manifest.json'))
    assert manifest['repository'] == 'xlbaoxl/canghuo-game'
    assert manifest['commit'] == 'e101fca146bf340d8738dbaa3931c827e4efc227'
    assert len(manifest['files']) == 173
    assert sum(x.file_size for x in source.infolist()) < 100 * 1024 * 1024
    names = set()
    for row in manifest['files']:
        path = PurePosixPath(row['path'])
        assert not path.is_absolute() and '..' not in path.parts and '\\' not in str(path)
        assert str(path) not in names
        names.add(str(path))
        info = source.getinfo(str(path))
        assert not stat.S_ISLNK(info.external_attr >> 16)
        body = source.read(str(path))
        assert len(body) == row['size']
        assert hashlib.sha256(body).hexdigest() == row['sha256']
        assert hashlib.sha1(b'blob ' + str(len(body)).encode() + b'\0' + body).hexdigest() == row['blob']
        assert not body.startswith(b'version https://git-lfs.github.com/spec/')
        if str(path).startswith('modules/training-camp/'):
            destination = path
        else:
            assert str(path) in ['docs/新版战斗.md', 'docs/战斗升级策划.md']
            destination = PurePosixPath('archive/game-e101fca/docs') / path.name
        target = ROOT / str(destination)
        assert target.resolve().is_relative_to(ROOT) and not target.is_symlink()
        if target.exists():
            assert target.read_bytes() == body, 'Refusing existing different file: ' + str(destination)
        prepared.append((target, body, dict(row, destination=str(destination))))
# Validate every input before writing any destination.
for target, body, _ in prepared:
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(body)
receipt = {
    'format': 1, 'source_repository': manifest['repository'], 'source_commit': manifest['commit'],
    'source_export_run': 37821554938, 'source_archive_sha256': hashlib.sha256(inner).hexdigest(),
    'scope': 'Exact bytes of existing 3.0.1 module and two historical design documents; not new gameplay',
    'files': [row for _, _, row in prepared], 'module_files': 171, 'historical_design_files': 2,
    'git_history_imported': False, 'runtime_executed_by_importer': False
}
(ROOT / 'migration').mkdir(exist_ok=True)
(ROOT / 'migration/source_manifest.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+'\n')
print('Verified and imported 173 source files; no world files or existing design documents replaced.')
