#!/usr/bin/env python3
"""Real browser regression on a headerless project subpath, or a deployed Pages URL.
All game actions use mouse input; the status bridge is read-only.
"""
from __future__ import annotations
import argparse
from functools import partial
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import threading
import traceback
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright

PREFIX = '/canghuo-combat/'

class HeaderlessHandler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, '.wasm': 'application/wasm', '.js': 'text/javascript'}
    def translate_path(self, path):
        path = '/' + path[len(PREFIX):] if path.startswith(PREFIX) else '/__not_a_game_path__'
        return super().translate_path(path)
    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()
    def log_message(self, *_args): pass


def test_pages(output: Path, root: Path | None = None, url: str | None = None,
               commit: str | None = None, executable: str | None = None) -> None:
    output.mkdir(parents=True, exist_ok=True)
    server = None
    if root:
        server = ThreadingHTTPServer(('127.0.0.1', 0), partial(HeaderlessHandler, directory=str(root)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f'http://127.0.0.1:{server.server_port}{PREFIX}'
        commit = json.loads((root / 'build.json').read_text())['commit']
    elif not url or not (url.startswith('https://') and urlparse(url).hostname == 'xlbaoxl.github.io' and urlparse(url).path == PREFIX):
        raise ValueError('Live validation requires the exact HTTPS project Pages URL')
    if not re.fullmatch('[0-9a-f]{40}', commit or ''):
        raise ValueError('An exact expected source commit is required')
    report = {'scope': 'Actual release WASM on headerless project subpath' if root else 'Actual public HTTPS GitHub Pages browser playthrough',
              'url': url, 'expected_commit': commit, 'success': False, 'checks': [], 'errors': []}
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False, executable_path=executable, args=[
            '--use-gl=angle', '--use-angle=gl', '--ignore-gpu-blocklist', '--disable-dev-shm-usage', '--no-sandbox'])
        report['browser_version'] = browser.version
        context = browser.new_context(viewport={'width': 1360, 'height': 900}, accept_downloads=True)
        page = context.new_page()
        page.on('pageerror', lambda error: report['errors'].append(str(error)))
        messages = []
        page.on('console', lambda msg: messages.append(msg.text))
        def check(ok, label):
            report['checks'].append({'label': label, 'pass': bool(ok)})
            print(('PASS ' if ok else 'FAIL ') + label, flush=True)
            (output / 'progress.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
            if not ok: raise AssertionError(label)
        def state(): return page.evaluate('window.canghuoStatus')
        def wait(expression, timeout=120000):
            page.wait_for_function('() => {const s=window.canghuoStatus;return s && (' + expression + ')}', timeout=timeout)
        def point(x, y):
            seq = state()['sample']
            rect = page.locator('#canvas').bounding_box()
            page.mouse.click(rect['x'] + x*rect['width']/1280, rect['y'] + y*rect['height']/720)
            wait('s.sample >= ' + str(seq + 2))
        def click(key):
            wait(f's.controls[{json.dumps(key)}] && !s.controls[{json.dumps(key)}].disabled')
            c = state()['controls'][key]; point(c['x'], c['y'])
        def target(key):
            c = state()['targets'][key]; point(c['x'], c['y'])
        def ready():
            wait('s.player_ready || s.page === "result"')
            check(state()['page'] == 'battle', 'player decision reached')
        def start():
            page.wait_for_function('window.CanghuoIsolation?.state === "ready" || window.CanghuoIsolation?.state === "error"', timeout=90000)
            check(page.evaluate('window.CanghuoIsolation.state') == 'ready', 'startup isolation ready without reload loop')
            page.click('#play')
            wait('s.page === "characters"', 240000)
        def capture(name):
            was_running = state()['page'] == 'battle' and not state()['paused']
            if was_running: click('pause'); wait('s.paused')
            page.screenshot(path=str(output / (name + '.png')), timeout=60000)
            if was_running: click('pause'); wait('!s.paused')
        try:
            # Raw requests do not use a Service Worker: prove the real host behavior.
            raw = context.request.get(url)
            check(raw.ok, 'project directory returns HTML')
            if root: check('cross-origin-opener-policy' not in raw.headers, 'host supplies no COOP header (Pages-equivalent)')
            manifest = context.request.get(url + 'build.json').json()
            check(manifest['commit'] == commit, 'served manifest is the expected source commit')
            for name, info in manifest['files'].items():
                if not re.fullmatch(r'index(?:\.[a-z0-9_-]+)+', name): raise AssertionError('bad runtime path')
                resource = context.request.get(url + name, timeout=180000)
                data = resource.body()
                if not resource.ok or len(data) != info['bytes'] or hashlib.sha256(data).hexdigest() != info['sha256']:
                    raise AssertionError('served file fingerprint mismatch: ' + name)
            check(True, 'all hosted runtime bytes match build manifest')
            page.goto(url + '?diagnostics=1', wait_until='domcontentloaded'); start()
            check(page.evaluate('crossOriginIsolated && typeof SharedArrayBuffer !== "undefined"'), 'thread prerequisites established by service worker')
            check(page.evaluate('new URL(navigator.serviceWorker.controller.scriptURL).pathname') == PREFIX + 'index.isolation.worker.js', 'worker stays within project scope')
            check(state()['build']['commit'] == commit, 'running WASM build identity matches deployed manifest')
            report['build'] = state()['build']; capture('01-characters')
            click('character_C01'); wait('s.page === "loadout"')
            click('templates'); click('template_balanced')
            click('enter'); click('mode_mirror'); click('choice_easy'); click('start')
            wait('s.page === "battle"')
            # Confirm each speed transition; frame progression alone can be stale.
            current_speed = state()['speed']
            for _ in range(2):
                if current_speed == 0: break
                expected_speed = {1: 3, 3: 0}[current_speed]
                click('speed')
                wait('s.speed === ' + str(expected_speed))
                current_speed = expected_speed
            check(current_speed == 0, 'skip animation selected through acknowledged widget transitions')
            ready(); capture('02-battle')
            snapshot = state()['snapshot']
            for _ in range(12):
                ready()
                if state()['window_kind'] == 'OPPORTUNITY': break
                before = state()['window_id']; click('skill_2'); target('p')
                wait('s.window_id !== ' + json.dumps(before))
            check(state()['window_kind'] == 'OPPORTUNITY', 'natural opportunity with real threaded opponent AI')
            window = state()['window_id']
            click('skill_3'); target('p'); ready()
            click('skill_0'); target('e'); ready()
            check(state()['window_id'] == window, 'two skills share one opportunity window')
            click('active_0'); target('p'); ready()
            check(state()['controls']['active_0']['disabled'] and state()['window_id'] == window, 'independent Cui is used once and locked')
            click('battle_menu'); click('abort'); click('confirm_abort'); wait('s.page === "result"')
            check(state()['result'] == 'aborted', 'abort remains distinct from defeat')
            click('retry'); ready()
            check(state()['snapshot'] == snapshot, 'retry restores frozen initial snapshot')
            click('auto'); wait('s.page === "result"', 300000)
            check(state()['result'] in ['player', 'enemy', 'draw', 'undecided'] and state()['accounting_ok'], 'complete battle reconciles without rule error')
            capture('03-result')
            page.click('#feedback'); page.wait_for_selector('#report[open]')
            with page.expect_download() as download: page.click('#download')
            download.value.save_as(str(output / 'browser-review.json'))
            review = json.loads((output / 'browser-review.json').read_text())
            check(review['build']['commit'] == commit and review['events'] and review['AI'] and review['accounting']['ok'], 'actual downloaded feedback includes version, events and AI')
            page.click('#close-report')
            page.wait_for_function('window.canghuoSaveStatus?.state === "saved"', timeout=45000)
            expected = state()['snapshot']
            page.reload(wait_until='domcontentloaded'); start()
            check(state()['snapshot'] == expected and bool(expected), 'IndexedDB frozen snapshot survives reload under service worker')
            check(page.evaluate('caches.keys()') == [], 'no service-worker game cache can pin an old version')
            # Only the update probe is simulated; no combat state or game resource is replaced.
            next_manifest = {**manifest, 'commit': 'f'*40 if commit != 'f'*40 else 'e'*40}
            page.evaluate('''async next => {
                const original = window.fetch;
                window.fetch = (input, options) => String(input)==='build.json'
                    ? Promise.resolve(new Response(JSON.stringify(next), {headers:{'Content-Type':'application/json'}}))
                    : original(input, options);
                try { await checkUpdate(); } finally { window.fetch=original; }
            }''', next_manifest)
            page.wait_for_selector('#update:not([hidden])')
            check(state()['build']['commit'] == commit and state()['page'] == 'characters', 'simulated update notification does not auto-reload current build')
            fatal = [m for m in messages + page.evaluate('window.canghuoErrors') if any(x in m for x in ['SCRIPT ERROR', 'Parse Error', 'RuntimeError', 'Aborted(', 'out of bounds', 'AI illegal'])]
            check(not fatal and not report['errors'], 'no script, WASM or browser exceptions')
            report['success'] = True
        except Exception:
            report['failure'] = traceback.format_exc()
            try:
                report['last_status'] = state()
                report['isolation_status'] = page.evaluate('window.CanghuoIsolation')
                page.screenshot(path=str(output / 'failure.png'), timeout=10000)
            except Exception: pass
            raise
        finally:
            (output / 'console.log').write_text('\n'.join(messages), encoding='utf-8')
            (output / 'browser-checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
            browser.close()
            if server: server.shutdown(); server.server_close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--root', type=Path); group.add_argument('--url')
    parser.add_argument('--expected-commit')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--chromium', default=os.environ.get('CHROMIUM_EXECUTABLE'))
    args = parser.parse_args()
    test_pages(args.output.resolve(), args.root.resolve() if args.root else None, args.url, args.expected_commit, args.chromium)
