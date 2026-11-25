// Fails if any MarketSync function is defined twice across the addon's Lua files.
// A second top-level definition silently replaces the first at load time, so an
// edit to the first one would do nothing (see the sync review, phase 0.9.8-rc1).
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '../MarketSync');
const files = [];
(function walk(dir) {
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    if (fs.statSync(full).isDirectory()) {
      if (name !== 'Libs' && name !== 'Media') walk(full);
    } else if (name.endsWith('.lua')) {
      files.push(full);
    }
  }
})(root);

const seen = new Map();
const duplicates = [];
for (const file of files) {
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  lines.forEach((line, i) => {
    const m = line.match(/^function (MarketSync\.[A-Za-z_][A-Za-z0-9_.]*)\(/);
    if (!m) return;
    const where = path.relative(root, file) + ':' + (i + 1);
    if (seen.has(m[1])) duplicates.push(m[1] + ' at ' + seen.get(m[1]) + ' and ' + where);
    else seen.set(m[1], where);
  });
}

if (duplicates.length > 0) {
  console.error('FAIL duplicate MarketSync definitions:\n  ' + duplicates.join('\n  '));
  process.exit(1);
}
console.log('PASS no shadowed MarketSync definitions (' + seen.size + ' functions checked)');
