#!/usr/bin/env python3
"""Validate this documentation archive, not gameplay or an engine migration.
Optional --artifacts-dir checks the already available original files by hash.
The tool never downloads, mutates source artifacts, or runs archived scripts.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import unquote, urlsplit

REQUIRED = [
    'README.md', 'AGENTS.md', 'docs/战斗设计总纲.md',
    'docs/战斗结算内核.md', 'docs/阵法技能.md',
    'docs/讨论共识与演变.md', 'docs/实施状态与迁移清单.md',
    'research/来源与文件成果索引.md', 'migration/artifact_inventory.json',
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def validate(root: Path, artifacts: Path | None) -> dict:
    errors: list[str] = []
    checks = 0
    links = 0
    for name in REQUIRED:
        checks += 1
        if not (root / name).is_file():
            errors.append('Missing required file: ' + name)
    for path in sorted(root.rglob('*.md')):
        if '.git' in path.parts:
            continue
        text = path.read_text(encoding='utf-8')
        checks += 1
        if sum(1 for line in text.splitlines() if line.lstrip().startswith('```')) % 2:
            errors.append('Unbalanced fenced block: ' + str(path.relative_to(root)))
        for destination in re.findall(r'\]\(([^)]+)\)', text):
            if urlsplit(destination).scheme or destination.startswith('#'):
                continue
            target = unquote(destination.split('#', 1)[0])
            if not target:
                continue
            resolved = (path.parent / target).resolve()
            links += 1
            checks += 1
            if not resolved.is_relative_to(root) or not resolved.exists():
                errors.append(f'Broken local link: {path.relative_to(root)} -> {destination}')
    manifest_path = root / 'migration/artifact_inventory.json'
    original_checks: list[dict] = []
    pending: list[str] = []
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        checks += 1
        if manifest.get('authoritative_repository') != 'xlbaoxl/canghuo-combat':
            errors.append('Wrong repository authority')
        names = set()
        for item in manifest['artifacts']:
            checks += 1
            name = item['name']
            if name in names or Path(name).name != name:
                errors.append('Duplicate or invalid artifact basename: ' + name)
            names.add(name)
            if not re.fullmatch(r'[0-9a-f]{64}', item.get('sha256', '')):
                errors.append('Invalid SHA256: ' + name)
            if item.get('repository_copy', '').startswith('pending'):
                pending.append(name)
            if artifacts is not None:
                original = artifacts / name
                exists = original.is_file()
                passed = exists and original.stat().st_size == item['bytes'] and sha256(original) == item['sha256']
                original_checks.append({'name': name, 'matched': passed})
                checks += 1
                if not passed:
                    errors.append('Original artifact missing or hash/size mismatch: ' + name)
    return {
        'status': 'PASS' if not errors else 'FAIL',
        'scope': 'Documentation paths, fenced blocks, source manifest and optional local artifact hashes only',
        'checks': checks, 'relative_links_checked': links,
        'original_artifacts_checked': original_checks,
        'pending_repository_artifact_copies': pending,
        'engine_project_present': (root / 'modules/training-camp/project/project.godot').is_file(),
        'gameplay_or_godot_executed': False,
        'errors': errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--artifacts-dir', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        result = validate(root, args.artifacts_dir.resolve() if args.artifacts_dir else None)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        result = {'status': 'FAIL', 'scope': 'documentation-only', 'errors': [str(exc)], 'gameplay_or_godot_executed': False}
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    print(text, end='')
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
