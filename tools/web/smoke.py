#!/usr/bin/env python3
"""Exercise the actual exported WASM through Chromium mouse/keyboard input.
The game supplies read-only widget geometry; tests never mutate Godot state.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import threading
import time
import traceback
from playwright.sync_api import sync_playwright
from serve import server


def test_web(root: Path, output: Path, executable: str | None = None, headed: bool = False, graphics: str = "mesa") -> None:
    output.mkdir(parents=True, exist_ok=True)
    host = server(root)
    thread = threading.Thread(target=host.serve_forever, daemon=True)
    thread.start()
    url = f'http://127.0.0.1:{host.server_port}/?diagnostics=1'
    report = {'scope': 'Real Chromium, exported WebAssembly, software WebGL, physical browser input',
              'url': url, 'checks': [], 'errors': [], 'success': False}
    page = None
    try:
        with sync_playwright() as playwright:
            graphics_args = ['--use-gl=angle', '--use-angle=gl', '--ignore-gpu-blocklist'] if graphics == 'mesa' else ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']
            options = {'headless': not headed, 'args': graphics_args + ['--disable-dev-shm-usage', '--no-sandbox']}
            if executable:
                options['executable_path'] = executable
            browser = playwright.chromium.launch(**options)
            report['browser_version'] = browser.version
            report['headed'] = headed
            report['graphics'] = graphics
            report['started_monotonic'] = time.monotonic()
            context = browser.new_context(viewport={'width': 1360, 'height': 900}, accept_downloads=True)
            page = context.new_page()
            page.on('pageerror', lambda error: report['errors'].append(str(error)))
            console_messages = []
            def log_console(message):
                console_messages.append(message.text)
                if message.text.startswith('CANGHUO_HEARTBEAT '):
                    report['heartbeat'] = json.loads(message.text[len('CANGHUO_HEARTBEAT '):])
                    (output / 'last-heartbeat.json').write_text(json.dumps(report['heartbeat'], ensure_ascii=False, indent=2))
                with (output / 'console.log').open('a', encoding='utf-8') as log:
                    log.write(message.type + ': ' + message.text + '\n')
            page.on('console', log_console)

            def check(condition: bool, label: str) -> None:
                report['checks'].append({'label': label, 'pass': bool(condition)})
                print(('PASS ' if condition else 'FAIL ') + label, flush=True)
                (output / 'browser-progress.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
                if not condition:
                    raise AssertionError(label)

            last_state = {}
            def trace(label: str, **fields) -> None:
                record = {'label': label, 'seconds': round(time.monotonic()-report['started_monotonic'], 3), **fields}
                with (output / 'actions.jsonl').open('a', encoding='utf-8') as log:
                    log.write(json.dumps(record, ensure_ascii=False) + '\n')
                print('BROWSER ' + json.dumps(record, ensure_ascii=False), flush=True)

            def state() -> dict:
                nonlocal last_state
                last_state = page.evaluate('window.canghuoStatus')
                return last_state

            def wait(expression: str, timeout: int = 120000) -> None:
                try:
                    page.wait_for_function('() => {const s=window.canghuoStatus; return s && (' + expression + ');}', timeout=timeout)
                except Exception:
                    # Capture before Playwright tears down the browser on exception.
                    report['wait_failed'] = expression
                    report['last_status'] = last_state
                    report['runtime_messages'] = console_messages
                    (output / 'browser-timeout.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
                    try:
                        page.screenshot(path=str(output / 'failure.png'), timeout=5000)
                    except Exception:
                        pass
                    raise

            def point(x: float, y: float, button: str = 'left') -> None:
                trace('input_start', x=x, y=y, button=button, heartbeat=report.get('heartbeat'))
                sample = state().get('sample', 0)
                rect = page.locator('#canvas').bounding_box()
                page.mouse.click(rect['x'] + x * rect['width'] / 1280, rect['y'] + y * rect['height'] / 720, button=button)
                # Wait for subsequent game frames, not an optimistic fixed sleep.
                wait('s.sample >= ' + str(sample + 2))
                trace('input_settled', sample=state().get('sample'), fps=state().get('fps'))

            def click(key: str) -> None:
                trace('control', key=key)
                wait(f's.controls[{json.dumps(key)}] && !s.controls[{json.dumps(key)}].disabled')
                control = state()['controls'][key]
                point(control['x'], control['y'])

            def target(name: str) -> None:
                control = state()['targets'][name]
                point(control['x'], control['y'])

            def ready() -> None:
                wait('s.player_ready || s.page === "result"')
                check(state()['page'] == 'battle', 'player decision reached')

            def capture(name: str) -> None:
                trace('capture', name=name)
                # Save state before capture too, so graphics stalls remain diagnosable.
                (output / (name + '-status.json')).write_text(json.dumps(state(), ensure_ascii=False, indent=2))
                was_running = state()['page'] == 'battle' and not state()['paused']
                if was_running:
                    click('pause')
                    wait('s.paused')
                try:
                    page.screenshot(path=str(output / (name + '.png')), full_page=False, timeout=60000)
                finally:
                    if was_running:
                        click('pause')
                        wait('!s.paused')

            def speed_zero() -> None:
                for _ in range(3):
                    if state()['speed'] == 0:
                        return
                    click('speed')
                check(state()['speed'] == 0, 'skip animation selected through widget')

            response = page.goto(url, wait_until='domcontentloaded')
            check(response.headers.get('cross-origin-opener-policy') == 'same-origin', 'COOP header')
            check(response.headers.get('cross-origin-embedder-policy') == 'require-corp', 'COEP header')
            page.click('#play')
            wait('s.page === "characters"', 240000)
            check(page.evaluate('crossOriginIsolated && typeof SharedArrayBuffer !== "undefined"'), 'real browser thread prerequisites')
            report['build'] = state()['build']
            capture('01-characters')
            click('character_C01')
            wait('s.page === "loadout"')
            click('templates')
            click('template_balanced')
            click('profile_power')
            wait('s.growth_profile === "power"')
            capture('02-loadout')
            click('profile_base')
            click('enter')
            capture('03-selector')
            click('selector_back')
            wait('!s.modal')
            check(state()['slots'] == ['sword_deep', 'ember', 'guard', 'qi'], 'cancel selector preserves equipment')
            click('enter')
            click('mode_mirror')
            click('choice_easy')
            click('start')
            wait('s.page === "battle"')
            speed_zero()
            ready()
            capture('04-battle')
            original = state()['snapshot']
            baseline_hash = state()['hash']
            click('passive_1')
            check(not state()['selected_action'] and state()['hash'] == baseline_hash, 'automatic artifact icon cannot cast')
            page.locator('#canvas').focus()
            page.keyboard.press('1')
            wait('s.selected_action.kind === "cast" && s.selected_action.slot === 0')
            point(1035, 540, 'right')
            wait('Object.keys(s.selected_action).length === 0')
            check(state()['hash'] == baseline_hash, 'keyboard skill selection and cancellation do not spend resources')
            click('active_1')
            wait('s.selected_action.kind === "artifact"')
            point(1035, 540, 'right')
            wait('Object.keys(s.selected_action).length === 0')
            check(state()['hash'] == baseline_hash, 'cancel Cui does not spend or replay auto')
            saw_opportunity = False
            for _ in range(12):
                ready()
                if state()['window_kind'] == 'OPPORTUNITY':
                    saw_opportunity = True
                    break
                before = state()['window_id']
                click('skill_2')
                target('p')
                wait('s.window_id !== ' + json.dumps(before))
            check(saw_opportunity, 'natural opportunity reached, with real threaded enemy AI')
            capture('05-opportunity')
            window = state()['window_id']
            click('skill_3')
            target('p')
            ready()
            click('skill_0')
            target('e')
            ready()
            check(state()['window_id'] == window, 'two legal skills used in one opportunity window')
            click('active_0')
            target('p')
            ready()
            check(state()['window_id'] == window and state()['controls']['active_0']['disabled'], 'independent Cui used and locked within opportunity')
            click('pause')
            wait('s.paused')
            paused_hash = state()['hash']
            page.wait_for_timeout(800)
            check(state()['hash'] == paused_hash, 'pause preserves battle state')
            click('pause')
            wait('!s.paused')
            click('battle_menu')
            click('abort')
            click('confirm_abort')
            wait('s.page === "result"')
            check(state()['result'] == 'aborted', 'abort is not defeat')
            click('retry')
            wait('s.page === "battle"')
            ready()
            check(state()['snapshot'] == original, 'original-condition retry restores frozen initial snapshot')
            speed_zero()
            click('auto')
            wait('s.page === "result"', 300000)
            check(state()['result'] in ['player', 'enemy', 'draw', 'undecided'], 'real automated battle reaches non-error terminal result')
            check(state()['accounting_ok'], 'final battle accounting reconciles')
            capture('06-result')
            page.click('#feedback')
            page.wait_for_selector('#report[open]')
            check('问题描述' in page.locator('#summary').input_value(), 'feedback summary available')
            with page.expect_download() as pending:
                page.click('#download')
            download = pending.value
            diagnostic = output / 'browser-review.json'
            download.save_as(str(diagnostic))
            data = json.loads(diagnostic.read_text(encoding='utf-8'))
            check(data['accounting']['ok'] and bool(data['events']) and bool(data['AI']), 'browser download contains actual battle, AI, accounting and build identity')
            check(data['build']['commit'] == report['build']['commit'], 'report bound to running build')
            page.click('#close-report')
            click('edit')
            click('back_characters')
            click('character_C02')
            click('profile_power')
            click('enter')
            click('mode_mirror')
            click('choice_easy')
            click('start')
            wait('s.page === "battle"')
            page.wait_for_timeout(2000)
            page.reload(wait_until='domcontentloaded')
            page.click('#play')
            wait('s.page === "characters"', 240000)
            check(state()['character'] == 'C02' and state()['growth_profile'] == 'power', 'IndexedDB settings survive a real page reload')
            check(bool(state()['snapshot']), 'frozen retry snapshot survives reload, not live running state')
            page.set_viewport_size({'width': 960, 'height': 760})
            click('character_C01')
            wait('s.page === "loadout"')
            check(page.evaluate('document.documentElement.scrollWidth <= innerWidth'), 'smaller desktop viewport has no horizontal overflow and clicks still align')
            capture('07-resized')
            # A deployment error must fail visibly before starting the engine.
            broken = server(root, no_isolation=True)
            bad_thread = threading.Thread(target=broken.serve_forever, daemon=True)
            bad_thread.start()
            bad_page = context.new_page()
            try:
                bad_page.goto(f'http://127.0.0.1:{broken.server_port}/', wait_until='domcontentloaded')
                bad_page.click('#play')
                check('跨源隔离' in bad_page.locator('#message').inner_text(), 'missing isolation headers produce an actionable startup error')
                bad_page.screenshot(path=str(output / '08-missing-headers.png'))
            finally:
                bad_page.close()
                broken.shutdown()
                broken.server_close()
            runtime_errors = console_messages + page.evaluate('window.canghuoErrors')
            report['runtime_messages'] = runtime_errors
            fatal = [message for message in runtime_errors if any(marker in message for marker in ('SCRIPT ERROR', 'Parse Error', 'RuntimeError', 'Aborted(', 'out of bounds', 'AI illegal'))]
            check(not fatal and not report['errors'], 'no script, WASM or browser exceptions')
            report['success'] = True
            browser.close()
    except Exception:
        report['failure'] = traceback.format_exc()
        if page is not None:
            try:
                page.screenshot(path=str(output / 'failure.png'), timeout=10000)
                report['last_status'] = page.evaluate('window.canghuoStatus')
            except Exception:
                pass
        raise
    finally:
        host.shutdown()
        host.server_close()
        (output / 'browser-checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--chromium', default=os.environ.get('CHROMIUM_EXECUTABLE'))
    parser.add_argument('--graphics', choices=['mesa', 'swiftshader'], default='mesa')
    parser.add_argument('--headed', action='store_true', help='Use a real X11 browser window (CI runs under Xvfb)')
    arguments = parser.parse_args()
    test_web(arguments.root.resolve(), arguments.output.resolve(), arguments.chromium, arguments.headed, arguments.graphics)
