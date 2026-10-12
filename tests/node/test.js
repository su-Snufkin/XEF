function fib(n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
const t0 = Date.now();
console.log('fib', fib(27));
const m = new Map(); for (let i = 0; i < 200000; i++) m.set('k' + (i % 1000), (m.get('k' + (i % 1000)) || 0) + i);
console.log('map', m.size, m.get('k7'));
const arr = Array.from({length: 300000}, (_, i) => (i * 2654435761) % 1000003); arr.sort((a, b) => a - b);
console.log('sort', arr[0], arr[arr.length - 1]);
let s = 0; for (const x of arr) s += Math.sqrt(x) * Math.sin(x); console.log('math', s.toFixed(6));
const o = JSON.parse(JSON.stringify({a: [1, 2, {b: 'x'.repeat(10)}], n: 1.5e300})); console.log('json', o.a[2].b.length, o.n);
console.log('regex', 'abc123def456'.replace(/\d+/g, m => `<${m}>`));
const crypto = require('crypto'); console.log('sha256', crypto.createHash('sha256').update('x'.repeat(100000)).digest('hex').slice(0, 16));
const zlib = require('zlib'); console.log('zlib', zlib.gunzipSync(zlib.gzipSync(Buffer.from('hello '.repeat(1000)))).length);
console.log('ms', Date.now() - t0 > 0);
