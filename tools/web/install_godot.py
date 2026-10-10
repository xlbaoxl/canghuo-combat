#!/usr/bin/env python3
"""Install the pinned official Godot editor and matching Web templates on Linux.
Downloads are checked against GitHub's SHA256 release-asset digest. No tokens
are forwarded to release-asset URLs. The same installer is used by CI/hosting.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import urllib.request
import zipfile

VERSION = '4.7.2'
RELEASE = f'https://api.github.com/repos/godotengine/godot-builds/releases/tags/{VERSION}-stable'
ENGINE_SHA256 = 'cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4'

def request(url: str):
    return urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'canghuo-web-build'}), timeout=120)

def verified_download(asset: dict, target: Path) -> str:
    digest = asset.get('digest', '')
    if not digest.startswith('sha256:') or len(digest) != 71:
        raise RuntimeError('Official release does not supply the required SHA256: ' + asset['name'])
    expected = digest[7:]
    if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest() != expected:
        partial = target.with_suffix(target.suffix + '.part')
        with request(asset['browser_download_url']) as response, partial.open('wb') as output:
            shutil.copyfileobj(response, output, length=1024 * 1024)
        actual = hashlib.sha256(partial.read_bytes()).hexdigest()
        if actual != expected:
            partial.unlink(missing_ok=True)
            raise RuntimeError('SHA256 mismatch: ' + asset['name'])
        partial.replace(target)
    return expected

def install(destination: Path) -> Path:
    destination = destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    with request(RELEASE) as response:
        release = json.load(response)
    if release['tag_name'] != VERSION + '-stable' or release['draft'] or release['prerelease']:
        raise RuntimeError('Unexpected Godot release identity')
    assets = {asset['name']: asset for asset in release['assets']}
    engine_asset = assets[f'Godot_v{VERSION}-stable_linux.x86_64.zip']
    template_asset = assets[f'Godot_v{VERSION}-stable_export_templates.tpz']
    if engine_asset.get('digest') != 'sha256:' + ENGINE_SHA256:
        raise RuntimeError('Godot editor differs from the verified repository baseline')
    engine_zip, template_zip = destination / 'engine.zip', destination / 'templates.tpz'
    receipt = {'version': VERSION, 'release': RELEASE, 'assets': []}
    for asset, path in [(engine_asset, engine_zip), (template_asset, template_zip)]:
        digest = verified_download(asset, path)
        receipt['assets'].append({'name': asset['name'], 'sha256': digest, 'url': asset['browser_download_url']})
    executable = destination / 'godot'
    with zipfile.ZipFile(engine_zip) as archive, archive.open(f'Godot_v{VERSION}-stable_linux.x86_64') as source, executable.open('wb') as output:
        shutil.copyfileobj(source, output)
    executable.chmod(0o755)
    templates = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'godot/export_templates' / (VERSION + '.stable')
    templates.mkdir(parents=True, exist_ok=True)
    installed = []
    with zipfile.ZipFile(template_zip) as archive:
        for member in archive.namelist():
            name = Path(member).name
            if member.startswith('templates/') and name.startswith('web') and name.endswith('.zip'):
                with archive.open(member) as source, (templates / name).open('wb') as output:
                    shutil.copyfileobj(source, output)
                installed.append(name)
    if not {'web_debug.zip', 'web_release.zip'}.issubset(installed):
        raise RuntimeError('Threaded Web export templates are missing: ' + repr(installed))
    receipt['templates'] = installed
    (destination / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(str(executable), flush=True)
    return executable

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dir', type=Path, default=Path('.local-verification/godot'))
    install(parser.parse_args().dir)
