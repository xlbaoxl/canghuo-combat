#!/usr/bin/env python3
"""Upload only a verified Web export to an existing, fully protected Vercel project.
No project creation, no protection changes, no source upload, no token logging.
The hosting integration must still be verified against the owner's connected account.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import time
import urllib.error
import urllib.parse
import urllib.request

HEADERS = {
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'require-corp',
    'Cross-Origin-Resource-Policy': 'same-origin',
    'Cache-Control': 'no-cache',
    'X-Content-Type-Options': 'nosniff',
    'X-Robots-Tag': 'noindex, nofollow',
}
SUITES = {'test_upgrade', 'test_presentation_upgrade', 'threaded_upgrade', 'test_upgrade_battles'}

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_args, **_kwargs):
        raise RuntimeError('Refusing to forward deployment credentials through a redirect')

class Client:
    def __init__(self, token: str, team: str = ''):
        if not token:
            raise ValueError('VERCEL_TOKEN must be configured as a protected CI secret')
        self.token, self.team = token, team
        self.opener = urllib.request.build_opener(NoRedirect())

    def request(self, method: str, path: str, data: dict | bytes | None = None, extra: dict | None = None) -> dict:
        if not path.startswith('/v') or '://' in path or '?' in path:
            raise ValueError('Unexpected API path')
        url = 'https://api.vercel.com' + path
        if self.team:
            url += '?' + urllib.parse.urlencode({'teamId': self.team})
        headers = {'Authorization': 'Bearer ' + self.token, 'User-Agent': 'canghuo-verified-web-deploy'}
        if isinstance(data, dict):
            data = json.dumps(data).encode('utf-8')
            headers['Content-Type'] = 'application/json'
        elif data is not None:
            headers['Content-Type'] = 'application/octet-stream'
        headers.update(extra or {})
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with self.opener.open(request, timeout=180) as response:
                body = response.read()
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as error:
            # Do not print authorization, signed URLs or account payloads.
            raise RuntimeError(f'Vercel API {method} {path} returned HTTP {error.code}') from None


def verified_files(root: Path, browser_report: Path, build_report: Path, commit: str) -> tuple[dict, dict[str, bytes]]:
    if not re.fullmatch('[0-9a-f]{40}', commit):
        raise ValueError('A full Git commit identity is required')
    meta = json.loads((root / 'build.json').read_text())
    browser = json.loads(browser_report.read_text())
    build = json.loads(build_report.read_text())
    if any(item.get('commit') != commit for item in [meta, browser.get('build', {}), build.get('build', {})]):
        raise ValueError('Build and browser evidence must refer to this exact commit')
    if meta.get('debug') or meta.get('source_dirty'):
        raise ValueError('Refusing debug or dirty-source deployment')
    checks = browser.get('checks', [])
    if browser.get('success') is not True or not checks or any(item.get('pass') is not True for item in checks) or browser.get('errors'):
        raise ValueError('Real browser verification is incomplete or failed')
    if build.get('original_source_unchanged') is not True or set(build.get('rule_suites_executed', [])) != SUITES:
        raise ValueError('Authoritative rule verification is incomplete')
    files = {}
    for name, expected in meta.get('files', {}).items():
        if not re.fullmatch(r'index(?:\.[a-z0-9_-]+)+', name) or Path(name).suffix not in {'.html', '.js', '.wasm', '.pck', '.png'}:
            raise ValueError('Refusing non-runtime file: ' + name)
        path = root / name
        if path.is_symlink() or not path.is_file():
            raise ValueError('Refusing missing or symbolic-link file: ' + name)
        data = path.read_bytes()
        if len(data) != expected['bytes'] or hashlib.sha256(data).hexdigest() != expected['sha256']:
            raise ValueError('Export fingerprint mismatch: ' + name)
        files[name] = data
    if not {'index.html', 'index.js', 'index.wasm', 'index.pck'}.issubset(files):
        raise ValueError('Incomplete Web export')
    files['build.json'] = json.dumps(meta, indent=2).encode('utf-8')
    files['robots.txt'] = b'User-agent: *\nDisallow: /\n'
    files['vercel.json'] = json.dumps({'version': 2, 'framework': None,
        'buildCommand': '', 'installCommand': '',
        'headers': [{'source': '/(.*)', 'headers': [{'key': key, 'value': value} for key, value in HEADERS.items()]}]}).encode()
    if sum(map(len, files.values())) > 95 * 1024 * 1024:
        raise ValueError('Export exceeds the conservative upload budget; review hosting limits before publishing')
    return meta, files


def deploy(client: Client, project_id: str, meta: dict, files: dict[str, bytes], production: bool = False) -> dict:
    if not re.fullmatch(r'prj_[A-Za-z0-9]+', project_id):
        raise ValueError('An existing VERCEL_PROJECT_ID is required; project auto-creation is prohibited')
    project = client.request('GET', '/v9/projects/' + project_id)
    if project.get('id') != project_id or (project.get('ssoProtection') or {}).get('deploymentType') != 'all':
        raise ValueError('Deployment blocked: Vercel Authentication must protect ALL deployments, including production')
    entries = []
    for name, data in sorted(files.items()):
        digest = hashlib.sha1(data).hexdigest()
        client.request('POST', '/v2/files', data, {'x-vercel-digest': digest, 'Content-Length': str(len(data))})
        entries.append({'file': name, 'sha': digest, 'size': len(data)})
    payload = {'name': project['name'], 'project': project_id, 'files': entries,
               'projectSettings': {'framework': None, 'buildCommand': '', 'installCommand': '', 'outputDirectory': '', 'rootDirectory': None},
               'meta': {'combatCommit': meta['commit'], 'combatVersion': meta['version'], 'verification': 'rules-and-real-chromium'}}
    if production:
        payload['target'] = 'production'
    result = client.request('POST', '/v13/deployments', payload)
    deployment_id = result.get('id', '')
    if not re.fullmatch(r'dpl_[A-Za-z0-9]+', deployment_id):
        raise RuntimeError('Hosting response did not contain a valid deployment ID')
    deadline = time.monotonic() + 600
    while result.get('readyState') != 'READY':
        if result.get('readyState') in {'ERROR', 'CANCELED'} or time.monotonic() >= deadline:
            raise RuntimeError('Hosting did not reach READY; existing production must not be reported as updated')
        time.sleep(5)
        result = client.request('GET', '/v13/deployments/' + deployment_id)
    if result.get('aliasError'):
        raise RuntimeError('The candidate is ready but stable URL assignment failed')
    return {'deployment_id': deployment_id, 'url': 'https://' + result['url'] if result.get('url') else None,
            'aliases': result.get('alias', []), 'commit': meta['commit'], 'protected_project_verified': True,
            'hosting_ready': True, 'public_http_and_browser_verified': False, 'production': production}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--browser-report', required=True, type=Path)
    parser.add_argument('--build-report', required=True, type=Path)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--production', action='store_true')
    args = parser.parse_args()
    meta, files = verified_files(args.root, args.browser_report, args.build_report, args.commit)
    result = deploy(Client(os.environ.get('VERCEL_TOKEN', ''), os.environ.get('VERCEL_TEAM_ID', '')),
                    os.environ.get('VERCEL_PROJECT_ID', ''), meta, files, args.production)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
