// Node.js smoke test for xef-osx (tests/darwin/node_test.sh): output must be identical on a real Mac.
const fs = require('fs');
const path = require('path');
console.log('hi', 1 + 1);
console.log('version', process.version, process.platform, process.arch);
const obj = { a: 1, b: [1, 2, 3], c: { d: 'x', e: null }, f: 1.5e300, g: -0 };
const js = JSON.stringify(obj);
console.log(js, JSON.stringify(JSON.parse(js)) === js);
console.log(JSON.stringify({ n: [0.1 + 0.2, 1 / 3, 2 ** 53, -1e-7, 123456789012345680000] }));
let sum = 0;
for (let i = 0; i < 1e6; i++) sum += i % 7;
console.log('loop', sum);
let s = '';
for (let i = 0; i < 200; i++) s += String.fromCharCode(97 + (i % 26));
console.log(s.length, s.slice(0, 30), s.toUpperCase().slice(-10), s.split('a').length, s.indexOf('xyz'), s.replace(/[aeiou]/g, '_').slice(0, 20));
console.log('padStart', 'x'.padStart(5, 'ab'), 'café'.normalize('NFD').length, encodeURIComponent('a b&c/é'));
console.log([5, 1, 4, 2, 3].sort((a, b) => a - b).join(), [3, 1, 2].map(x => x * x).reduce((a, b) => a + b));
console.log(parseInt('ff', 16), parseFloat('3.25abc'), (255).toString(2), (0.000001234).toExponential(2), (1234.5678).toFixed(2), Math.fround(5.5), Math.hypot(3, 4));
const d = new Date(Date.UTC(2020, 1, 29, 12, 30, 45));
console.log(d.toISOString(), d.getUTCDay());
console.log(new Map([[1, 'a'], [2, 'b']]).size, new Set([1, 1, 2]).size, typeof Symbol(), 10n ** 20n);
const tmp = path.join(require('os').tmpdir(), 'xef_node_test_' + process.pid + '.txt');
fs.writeFileSync(tmp, 'line1\nline2\n');
console.log(fs.readFileSync(tmp, 'utf8').split('\n').length, fs.statSync(tmp).size, fs.existsSync(tmp));
fs.unlinkSync(tmp);
console.log(path.basename('/a/b/c.txt', '.txt'), path.resolve('/a/b', '../c'));
class A { #p = 1; get p() { return this.#p; } static s = 'st'; }
console.log(new A().p, A.s, [..."héllo"].length);
try { null.x; } catch (e) { console.log(e instanceof TypeError, e.message); }
const order = [];
setImmediate(() => order.push('immediate'));
process.nextTick(() => order.push('tick'));
Promise.resolve().then(() => order.push('promise'));
(async () => {
  await null;
  order.push('async');
  await new Promise(r => setImmediate(r));
  await new Promise(r => setTimeout(r, 20));
  order.push('timeout20');
  const data = await new Promise((res, rej) => fs.readFile(__filename, (err, d) => err ? rej(err) : res(d)));
  order.push('readFile ' + (data.length > 100));
  const t = await fs.promises.readFile(__filename, 'utf8');
  order.push('promises.readFile ' + t.startsWith('// Node.js'));
  await new Promise(r => process.nextTick(r));
  await Promise.all([1, 2, 3].map(n => new Promise(r => setTimeout(() => r(n), 10 * (4 - n)))));
  order.push('all');
  console.log(order.join(' | '));
})();
process.on('exit', (c) => console.log('exit', c));
