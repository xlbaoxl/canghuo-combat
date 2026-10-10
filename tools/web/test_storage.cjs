'use strict';
const assert = require('node:assert/strict');
const { readPersisted, createMonitor } = require('../../modules/training-camp/web/storage.js');

async function tests() {
  let checks = 0;
  const test = async (name, run) => { await run(); ++checks; console.log('PASS ' + name); };
  await test('save acknowledgement waits for actual bytes', async () => {
    let reads = 0, time = 0; const states = [];
    const monitor = createMonitor(async () => ++reads < 3 ? 'older' : 'newer', value => states.push(value),
      { now: () => time, delay: async ms => { time += ms; } });
    assert.equal(await monitor.request('newer', '/userfs/settings.json'), true);
    assert.equal(reads, 3);
    assert.deepEqual(states.map(s => s.state), ['pending', 'saved']);
  });
  await test('late acknowledgement cannot mark a newer save complete', async () => {
    const resolve = []; const states = [];
    const monitor = createMonitor(() => new Promise(done => resolve.push(done)), value => states.push(value));
    const older = monitor.request('old', '/userfs/settings.json');
    const newer = monitor.request('new', '/userfs/settings.json');
    resolve[0]('old'); assert.equal(await older, false);
    assert.equal(monitor.getStatus().state, 'pending');
    resolve[1]('new'); assert.equal(await newer, true);
    assert.deepEqual(states.filter(s => s.state === 'saved').map(s => s.revision), [2]);
  });
  await test('timeout never becomes successful save', async () => {
    let time = 0;
    const monitor = createMonitor(async () => null, () => {},
      { timeout: 200, now: () => time, delay: async ms => { time += ms; } });
    assert.equal(await monitor.request('new', '/userfs/settings.json'), false);
    assert.equal(monitor.getStatus().state, 'error');
  });
  await test('storage error is visible and a later save can recover', async () => {
    let time = 0, fail = true;
    const monitor = createMonitor(async () => { if (fail) throw new Error('denied'); return 'ok'; }, () => {},
      { timeout: 100, now: () => time, delay: async ms => { time += ms; } });
    assert.equal(await monitor.request('ok', '/userfs/settings.json'), false);
    assert.equal(monitor.getStatus().error, 'denied');
    fail = false;
    assert.equal(await monitor.request('ok', '/userfs/settings.json'), true);
  });
  await test('explicit write failure invalidates an in-flight acknowledgement', async () => {
    let done;
    const monitor = createMonitor(() => new Promise(resolve => { done = resolve; }), () => {});
    const pending = monitor.request('data', '/userfs/settings.json');
    monitor.fail('write failed'); done('data');
    assert.equal(await pending, false);
    assert.equal(monitor.getStatus().error, 'write failed');
  });
  await test('no matching database causes no open or writes', async () => {
    const idb = { databases: async () => [{ name: 'unrelated' }, { name: '/otherfs' }],
      open() { throw new Error('must not open'); } };
    assert.equal(await readPersisted('/userfs/settings.json', idb), null);
  });
  await test('browser without database enumeration reports unsupported', async () => {
    await assert.rejects(readPersisted('/userfs/settings.json', {}), /不支持/);
  });
  await test('IDBFS readback uses only readonly transaction and closes the database', async () => {
    let closed = false;
    const path = '/userfs/training_camp_v3/settings.json';
    const idb = {
      databases: async () => [{ name: '/userfs' }],
      open(name) {
        assert.equal(name, '/userfs');
        const request = {};
        request.result = {
          close() { closed = true; }, objectStoreNames: { contains: name => name === 'FILE_DATA' },
          transaction(name, mode) {
            assert.equal(name, 'FILE_DATA'); assert.equal(mode, 'readonly');
            const tx = { objectStore: () => ({ get(key) {
              assert.equal(key, path);
              const record = { result: { contents: new TextEncoder().encode('配置') } };
              setImmediate(() => { record.onsuccess(); tx.oncomplete(); });
              return record;
            } }) };
            return tx;
          }
        };
        setImmediate(() => request.onsuccess());
        return request;
      }
    };
    assert.equal(await readPersisted(path, idb), '配置');
    assert.equal(closed, true);
  });
  await test('database removed between enumeration and open is not recreated', async () => {
    let aborted = false;
    const idb = { databases: async () => [{ name: '/userfs' }], open() {
      const request = { transaction: { abort() { aborted = true; } } };
      setImmediate(() => request.onupgradeneeded()); return request;
    } };
    await assert.rejects(readPersisted('/userfs/settings.json', idb), /清理/);
    assert.equal(aborted, true);
  });
  console.log(`STORAGE_ACK checks=${checks} failures=0`);
}
tests().catch(error => { console.error(error); process.exitCode = 1; });
