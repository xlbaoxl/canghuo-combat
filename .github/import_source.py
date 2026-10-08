"""One-time migration of the author's pinned private combat project.
Downloads only short-lived file-service URLs provided in the private request.
Never extracts workflow files, credentials, world state or arbitrary archive paths.
"""
from pathlib import Path, PurePosixPath
import hashlib, io, json, os, shutil, stat, urllib.parse, urllib.request, zipfile

ROOT=Path.cwd().resolve()
OUT=Path(os.environ['RUNNER_TEMP'])/'combat-migration'
OUT.mkdir(parents=True,exist_ok=True)
req=json.loads((ROOT/'.migration/request.json').read_text())
assert req['source_commit']=='e101fca146bf340d8738dbaa3931c827e4efc227'

def obtain(entry):
    host=urllib.parse.urlsplit(entry['url']).hostname or ''
    assert host.endswith('.oaiusercontent.com'), 'Unapproved transport host'
    print('::add-mask::'+entry['url'])
    with urllib.request.urlopen(entry['url'],timeout=90) as response:
        data=response.read(160_000_001)
    assert len(data)<=160_000_000
    assert hashlib.sha256(data).hexdigest()==entry['sha256'], 'Archive hash mismatch'
    return data

def safe(name):
    path=PurePosixPath(name)
    assert not path.is_absolute() and '..' not in path.parts and '\\' not in name
    p=ROOT/name
    assert p.resolve().is_relative_to(ROOT) and not p.is_symlink()
    return p

source=obtain(req['source'])
with zipfile.ZipFile(io.BytesIO(source)) as envelope:
    raw=envelope.read('combat-source.zip')
    expected=envelope.read('archive-sha256.txt').decode().strip()
assert hashlib.sha256(raw).hexdigest()==expected
prepared=[]
with zipfile.ZipFile(io.BytesIO(raw)) as archive:
    manifest=json.loads(archive.read('source-manifest.json'))
    assert manifest['repository']=='xlbaoxl/canghuo-game' and manifest['commit']==req['source_commit']
    expected_names={'source-manifest.json'}|{r['path'] for r in manifest['files']}
    assert set(archive.namelist())==expected_names and len(archive.namelist())==len(expected_names)
    for row in manifest['files']:
        name=row['path']
        assert name.startswith('modules/training-camp/') or name in ['docs/新版战斗.md','docs/战斗升级策划.md']
        assert '.git' not in PurePosixPath(name).parts and '.godot' not in PurePosixPath(name).parts
        p=safe(name)
        assert not p.exists(), 'Concurrent destination already exists: '+name
        data=archive.read(name)
        assert len(data)==row['size'] and hashlib.sha256(data).hexdigest()==row['sha256']
        assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==row['blob']
        prepared.append((p,data))
for p,data in prepared:
    p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
    if p.suffix=='.sh':p.chmod(0o755)
record=ROOT/'migration/source_manifest.json'
record.parent.mkdir(parents=True,exist_ok=True)
record.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
for name in ['新版战斗.md','战斗升级策划.md']:
    p=ROOT/'archive/implementation-3.0.1/docs'/name
    p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/'docs'/name,p)

# Historical delivery archives remain release assets, not mutable source code.
for key,filename in [('evidence','verification-3.0.1.zip'),('windows','CanghuoTraining-3.0.1-Windows.zip')]:
    data=obtain(req[key]);(OUT/filename).write_bytes(data)
    if key=='evidence':
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            for name in z.namelist():
                if name.endswith('/') or not name.endswith(('.md','.json','.log','.txt')):continue
                p=safe('verification/history/3.0.1/'+name)
                p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(z.read(name))
receipt={'source_repository':manifest['repository'],'source_commit':manifest['commit'],'source_files':len(prepared),'mode':'byte-preserving snapshot import; not a gameplay update','source_archive_sha256':expected,'history_artifacts':{k:{'sha256':req[k]['sha256'],'origin':req[k]['origin']} for k in ['evidence','windows']},'source_export_run':req['source_export_run']}
(ROOT/'migration/import_receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
(OUT/'receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print('Imported',len(prepared),'pinned project files; no game rules were changed.')
