#!/usr/bin/env python3
"""Loopback-only test server. Not a public production server."""
from __future__ import annotations
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

class Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.js': 'text/javascript'}
    def end_headers(self):
        if not getattr(self.server, 'no_isolation', False):
            self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
            self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cross-Origin-Resource-Policy', 'same-origin')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        super().end_headers()
    def log_message(self, *_args):
        pass

def server(root: Path, port: int = 0, no_isolation: bool = False) -> ThreadingHTTPServer:
    if not (root / 'index.html').is_file():
        raise ValueError('Serve an actual Web export directory, not the source repository')
    result = ThreadingHTTPServer(('127.0.0.1', port), partial(Handler, directory=str(root.resolve())))
    result.no_isolation = no_isolation
    return result

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--port', type=int, default=8060)
    parser.add_argument('--no-isolation', action='store_true')
    args = parser.parse_args()
    instance = server(args.root, args.port, args.no_isolation)
    print(f'http://127.0.0.1:{instance.server_port}', flush=True)
    instance.serve_forever()
