/* Network-only isolation adapter. Deliberately does not implement offline/PWA caching.
 * Scoped to this game's directory, never to other repositories on the same origin.
 */
'use strict';
self.addEventListener('install', event => event.waitUntil(self.skipWaiting()));
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  const scope = new URL(self.registration.scope);
  if (request.method !== 'GET' || url.origin !== scope.origin || !url.pathname.startsWith(scope.pathname)) return;
  if (request.cache === 'only-if-cached' && request.mode !== 'same-origin') return;
  event.respondWith((async () => {
    const response = await fetch(request, {cache: 'no-cache'});
    if (response.type === 'opaque' || response.status === 0) return response;
    const headers = new Headers(response.headers);
    headers.set('Cross-Origin-Opener-Policy', 'same-origin');
    headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
    headers.set('Cross-Origin-Resource-Policy', 'same-origin');
    headers.set('Cache-Control', 'no-cache');
    // fetch() has decoded the body; do not misdescribe its length/encoding.
    headers.delete('Content-Encoding');
    headers.delete('Content-Length');
    return new Response(response.body, {status: response.status, statusText: response.statusText, headers});
  })());
});
