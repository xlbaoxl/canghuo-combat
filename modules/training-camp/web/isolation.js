/* Startup-only cross-origin isolation for hosts such as GitHub Pages.
 * No game cache, no credentials, no automatic reload after the game starts.
 */
(() => {
  'use strict';
  const button = document.getElementById('play');
  const message = document.getElementById('message');
  const base = new URL('./', location.href);
  const key = 'canghuo-isolation-reload:' + base.pathname;
  const state = window.CanghuoIsolation = {state: 'preparing', scope: base.pathname};
  const showError = error => {
    state.state = 'error';
    state.error = String(error.message || error);
    button.disabled = true;
    message.textContent = '浏览器隔离环境准备失败：' + state.error + '。请允许此站点使用 Service Worker，并使用电脑 Chrome/Edge 打开。';
  };
  if (window.crossOriginIsolated && typeof SharedArrayBuffer !== 'undefined') {
    state.state = 'ready';
    try { sessionStorage.removeItem(key); } catch (_) { /* No persistent data needed. */ }
    return;
  }
  button.disabled = true;
  if (!window.isSecureContext || !('serviceWorker' in navigator)) {
    showError('需要 HTTPS 与 Service Worker 支持');
    return;
  }
  message.textContent = '首次进入正在准备 AI 多线程环境，完成后可点击进入训练营…';
  let timeout;
  const prepare = async () => {
    if (sessionStorage.getItem(key)) throw new Error('自动初始化后仍缺少跨源隔离，已停止重复刷新');
    const workerURL = new URL('index.isolation.worker.js', base);
    const registration = await navigator.serviceWorker.register(workerURL.href, {
      scope: base.pathname, updateViaCache: 'none'
    });
    await navigator.serviceWorker.ready;
    if (!navigator.serviceWorker.controller || navigator.serviceWorker.controller.scriptURL !== workerURL.href) {
      await new Promise(resolve => {
        const changed = () => {
          if (navigator.serviceWorker.controller?.scriptURL === workerURL.href) {
            navigator.serviceWorker.removeEventListener('controllerchange', changed);
            resolve();
          }
        };
        navigator.serviceWorker.addEventListener('controllerchange', changed);
        changed();
      });
    }
    // This path runs only before the engine is allowed to start, at most once/tab.
    if (state.state === 'error') return;
    if (window.canghuoStatus) throw new Error('游戏已经启动，未自动刷新');
    sessionStorage.setItem(key, '1');
    state.state = 'reloading';
    clearTimeout(timeout);
    location.reload();
    return registration;
  };
  Promise.race([
    prepare(),
    new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error('初始化超时，请刷新重试')), 30000); })
  ]).catch(showError).finally(() => clearTimeout(timeout));
})();
