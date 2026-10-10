#!/usr/bin/env python3
"""Build the existing game for Web in an isolated staging copy, never patch source.
The browser adapter subclasses the original controller. No second combat ruleset.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'modules/training-camp/project'
ADAPTER = ROOT / 'modules/training-camp/web'
SUITES = ('test_upgrade', 'test_presentation_upgrade', 'threaded_upgrade', 'test_upgrade_battles')
HEADERS = {
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'require-corp',
    'Cross-Origin-Resource-Policy': 'same-origin',
    'Cache-Control': 'no-cache',
    'X-Content-Type-Options': 'nosniff',
    'X-Robots-Tag': 'noindex, nofollow',
}

def fingerprints(root: Path) -> dict[str, str]:
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file() and '.godot' not in p.parts and not p.name.endswith('.import')}

def prepare(stage: Path, metadata: dict) -> None:
    if stage.exists():
        raise ValueError('Staging destination must not exist')
    shutil.copytree(SOURCE, stage, ignore=shutil.ignore_patterns('.godot', '*.import', '__pycache__'))
    shutil.copytree(ADAPTER, stage / 'web')
    project = (stage / 'project.godot').read_text(encoding='utf-8')
    substitutions = {
        'run/main_scene="res://main.tscn"': 'run/main_scene="res://web/main.tscn"',
        'renderer/rendering_method="mobile"': 'renderer/rendering_method="gl_compatibility"',
        'PackedStringArray("4.7", "Mobile")': 'PackedStringArray("4.7", "GL Compatibility")',
    }
    for old, new in substitutions.items():
        if project.count(old) != 1:
            raise ValueError('Source project changed; review Web adaptation: ' + old)
        project = project.replace(old, new)
    (stage / 'project.godot').write_text(project, encoding='utf-8')
    shutil.copyfile(ADAPTER / 'export_presets.cfg', stage / 'export_presets.cfg')
    (stage / 'web/build.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')

def run(command: list[str], log: Path, env: dict[str, str], timeout: int = 600) -> None:
    result = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout)
    log.write_text(result.stdout, encoding='utf-8')
    print(result.stdout, flush=True)
    if result.returncode or re.search(r'SCRIPT ERROR:|Parse Error:|Failed to load script', result.stdout):
        raise RuntimeError(f'Command failed; see {log}: {command}')

def build(engine: Path, output: Path, debug: bool = False, verify: bool = False) -> dict:
    engine, output = engine.resolve(), output.resolve()
    # Refuse destructive/ambiguous output directories. Export only into a new folder.
    if output.exists():
        raise ValueError('Output already exists; choose an empty/new build directory: ' + str(output))
    if output == ROOT or output in ROOT.parents or output.is_relative_to(SOURCE):
        raise ValueError('Unsafe output path')
    version = subprocess.check_output([str(engine), '--version'], text=True).strip()
    if not version.startswith('4.7.2.stable'):
        raise ValueError('Expected verified Godot 4.7.2.stable, got ' + version)
    commit = os.environ.get('GITHUB_SHA') or os.environ.get('VERCEL_GIT_COMMIT_SHA') or subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    metadata = {'version': '3.0.1-web.2', 'commit': commit, 'engine': version,
                'built_at': datetime.now(timezone.utc).isoformat(), 'debug': debug,
                'source_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()),
                'source': 'modules/training-camp/project', 'threaded': True}
    before = fingerprints(SOURCE)
    output.mkdir(parents=True)
    logs = output.parent / (output.name + '-evidence')
    logs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='canghuo-web-') as temporary:
        stage = Path(temporary) / 'project'
        prepare(stage, metadata)
        # Only project/export configuration differs; rules, data, assets stay byte-identical.
        staged = fingerprints(stage)
        changed = [name for name, digest in before.items() if staged.get(name) != digest]
        if sorted(changed) != ['export_presets.cfg', 'project.godot']:
            raise RuntimeError('Unexpected runtime modifications: ' + repr(changed))
        env = dict(os.environ, UPGRADE_VERIFY_DIR=str(logs.resolve()))
        base = [str(engine), '--headless', '--path', str(stage)]
        run(base + ['--editor', '--import', '--quit'], logs / 'import.log', env)
        if verify:
            for suite in SUITES:
                run(base + ['--script', f'res://tests/{suite}.gd'], logs / (suite + '.log'), env)
        run(base + ['--export-debug' if debug else '--export-release', 'Training Web', str(output / 'index.html')], logs / 'export.log', env)
    if fingerprints(SOURCE) != before:
        raise RuntimeError('Web build modified the authoritative source')
    # The helper follows the runtime-only index.* publication allowlist.
    shutil.copyfile(ADAPTER / 'storage.js', output / 'index.storage.js')
    for required in ('index.html', 'index.js', 'index.wasm', 'index.pck', 'index.storage.js'):
        if not (output / required).is_file() or not (output / required).stat().st_size:
            raise RuntimeError('Missing Web export: ' + required)
    metadata['files'] = {p.name: {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                         for p in sorted(output.iterdir()) if p.is_file()}
    (output / 'build.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    (output / '_headers').write_text('/*\n' + ''.join(f'  {key}: {value}\n' for key, value in HEADERS.items()), encoding='utf-8')
    (output / 'robots.txt').write_text('User-agent: *\nDisallow: /\n', encoding='utf-8')
    (logs / 'build-result.json').write_text(json.dumps({'build': metadata, 'original_source_unchanged': True, 'staged_overrides': changed, 'rule_suites_executed': list(SUITES) if verify else [], 'browser_tested': False}, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(metadata, indent=2), flush=True)
    return metadata

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    build(args.engine, args.output, args.debug, args.verify)
