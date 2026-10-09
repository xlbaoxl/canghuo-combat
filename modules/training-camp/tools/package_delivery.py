"""Package an already verified Windows executable and committed complete source.
No engine runtime, user saves, import cache or unrelated local work is copied.
"""
import argparse, hashlib, json, shutil, subprocess, zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REPO=ROOT.parents[1]
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def write_json(path,value):
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--destination',required=True)
    ap.add_argument('--checks',required=True)
    ap.add_argument('--ui',required=True)
    args=ap.parse_args()
    destination=Path(args.destination).resolve()
    destination.mkdir(parents=True,exist_ok=True)
    checks=Path(args.checks)
    ui=Path(args.ui)
    for name in ['rules.json','battles.json','corpus-compatibility.json','threaded-ai.json','presentation.json']:
        result=json.loads((checks/name).read_text(encoding='utf-8-sig'))
        if result.get('errors') or result.get('failures'):raise RuntimeError(name+' contains failures')
    for name in ['ui-checks.json','reload-check.json']:
        result=json.loads((ui/name).read_text(encoding='utf-8-sig'))
        if result.get('errors') or result.get('failures'):raise RuntimeError(name+' contains failures')
    dirty=subprocess.check_output(['git','status','--porcelain'],cwd=REPO,text=True)
    if dirty.strip():raise RuntimeError('Commit source before packaging')
    commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()
    package=destination/'CanghuoTraining-v2-Windows'
    package.mkdir(exist_ok=True)
    shutil.copy2(ROOT/'builds/CanghuoTraining.exe',package/'CanghuoTraining.exe')
    for name in ['PLAY_GUIDE.md','TEST_REPORT.md']:
        shutil.copy2(ROOT/name,package/name)
    license_dir=package/'licenses'
    license_dir.mkdir(exist_ok=True)
    for name in ['Godot-LICENSE.txt','Godot-COPYRIGHT.txt']:
        shutil.copy2(ROOT/'project/assets/licenses'/name,license_dir/name)
    for name in ['OFL.txt','SOURCE.md']:
        shutil.copy2(ROOT/'project/assets/fonts'/name,license_dir/name)
    shutil.copy2(ROOT/'project/assets/ART_SOURCES.md',license_dir/'ART_SOURCES.md')
    evidence=package/'verification'
    evidence.mkdir(exist_ok=True)
    for name in ['rules.json','battles.json','corpus-compatibility.json','threaded-ai.json','presentation.json']:
        shutil.copy2(checks/name,evidence/name)
    for source in ui.iterdir():
        if source.suffix in ['.png','.json']:shutil.copy2(source,evidence/source.name)
    manifest={'source_commit':commit,'rules':'own-window-1.0','content':'training-v2.1','ui_version':'2.2.2',
              'platform':'Windows x86_64 / Godot 4.7.2 / D3D12 Mobile',
              'exe_sha256':sha(package/'CanghuoTraining.exe'),
              'files':{p.relative_to(package).as_posix():sha(p) for p in package.rglob('*') if p.is_file() and p.name!='SOURCE_MANIFEST.json'}}
    write_json(package/'SOURCE_MANIFEST.json',manifest)
    windows_zip=destination/'CanghuoTraining-v2-Windows.zip'
    with zipfile.ZipFile(windows_zip,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for path in package.rglob('*'):
            if path.is_file():archive.write(path,path.relative_to(destination).as_posix())
    source_zip=destination/'CanghuoTraining-v2-Source.zip'
    subprocess.run(['git','archive','--format=zip','--prefix=CanghuoTraining-v2-Source/',
                    '-o',str(source_zip),'HEAD'],cwd=REPO,check=True)
    hashes={'source_commit':commit,'windows_zip_sha256':sha(windows_zip),
            'source_zip_sha256':sha(source_zip),'exe_sha256':manifest['exe_sha256']}
    write_json(destination/'SHA256.json',hashes)
    print(json.dumps({'destination':str(destination),**hashes},ensure_ascii=False))
if __name__=='__main__':main()
