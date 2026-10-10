/* Read-only acknowledgements for Godot's existing IDBFS; never a second save store. */
(function (root) {
  'use strict';
  async function readPersisted(path, idb = root.indexedDB) {
    if (!idb || typeof idb.databases !== 'function') {
      throw new Error('当前浏览器不支持存储回读确认');
    }
    const databases = await idb.databases();
    const names = databases.map(db => db.name).filter(name =>
      typeof name === 'string' && name.startsWith('/') && path.startsWith(name.replace(/\/$/, '') + '/'));
    names.sort((a, b) => b.length - a.length);
    if (!names.length) return null;
    return new Promise((resolve, reject) => {
      let db, done = false;
      const finish = (error, value) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        if (db) db.close();
        if (error) reject(error); else resolve(value);
      };
      const timer = setTimeout(() => finish(new Error('浏览器存储回读超时')), 5000);
      // Only open a database already enumerated above. If it disappears, abort creation.
      const request = idb.open(names[0]);
      request.onupgradeneeded = () => {
        request.transaction.abort();
        finish(new Error('浏览器存储已被清理'));
      };
      request.onerror = () => finish(request.error || new Error('无法读取浏览器存储'));
      request.onblocked = () => finish(new Error('浏览器存储被其他页面占用'));
      request.onsuccess = () => {
        db = request.result;
        if (done) { db.close(); return; }
        db.onversionchange = () => { db.close(); finish(new Error('浏览器存储发生版本变化')); };
        if (!db.objectStoreNames.contains('FILE_DATA')) { finish(new Error('无法识别引擎存储结构')); return; }
        let text = null;
        try {
          const transaction = db.transaction('FILE_DATA', 'readonly');
          const record = transaction.objectStore('FILE_DATA').get(path);
          record.onsuccess = () => {
            try {
              if (record.result && record.result.contents != null) {
                text = new TextDecoder().decode(new Uint8Array(record.result.contents));
              }
            } catch (error) { finish(error); }
          };
          transaction.oncomplete = () => finish(null, text);
          transaction.onerror = () => finish(transaction.error || new Error('浏览器存储读取失败'));
          transaction.onabort = () => finish(transaction.error || new Error('浏览器存储读取中止'));
        } catch (error) { finish(error); }
      };
    });
  }

  function createMonitor(read, publish, options = {}) {
    const now = options.now || (() => Date.now());
    const delay = options.delay || (ms => new Promise(resolve => setTimeout(resolve, ms)));
    const timeout = options.timeout ?? 15000;
    let revision = 0;
    let status = { revision: 0, state: 'idle', path: '', error: '' };
    function emit(next) { status = next; publish({ ...next }); }
    async function request(raw, path) {
      const current = ++revision;
      const started = now();
      emit({ revision: current, state: 'pending', path, error: '' });
      let errorText = '';
      do {
        try {
          const stored = await read(path);
          if (current !== revision) return false;
          if (stored === raw) {
            emit({ revision: current, state: 'saved', path, error: '' });
            return true;
          }
          errorText = '';
        } catch (error) { errorText = String(error.message || error); }
        if (current !== revision) return false;
        if (now() - started >= timeout) break;
        await delay(100);
      } while (current === revision);
      if (current !== revision) return false;
      emit({ revision: current, state: 'error', path,
        error: errorText || '尚未确认配置写入浏览器；请保留诊断记录，不要立即刷新' });
      return false;
    }
    function fail(error) {
      ++revision;
      emit({ revision, state: 'error', path: status.path, error: String(error) });
    }
    return Object.freeze({ request, fail, getStatus: () => ({ ...status }) });
  }
  const api = Object.freeze({ readPersisted, createMonitor });
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.CanghuoStorage = api;
})(globalThis);
