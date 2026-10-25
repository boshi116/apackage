const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const publisher = path.resolve('.github/workflows/publish.sh');

function fixture(t, options = {}) {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'argon-release-'));
	t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
	fs.mkdirSync(path.join(dir, 'mock-bin'));
	fs.mkdirSync(path.join(dir, 'packages'));
	fs.writeFileSync(path.join(dir, 'Makefile'), 'PKG_VERSION:=2.0.0\nPKG_RELEASE:=1\n');
	const files = ['luci-app-argon-config-2.0.0-r1.apk', 'luci-app-argon-config_2.0.0-r1_all.ipk',
		'luci-i18n-argon-config-app-zh-cn-2.0.0-r1.apk'];
	for (const name of files) {
		if (options.omitIpk && name.endsWith('.ipk')) continue;
		fs.writeFileSync(path.join(dir, 'packages', name), 'package bytes: ' + name);
	}
	const log = path.join(dir, 'gh.jsonl');
	fs.writeFileSync(path.join(dir, 'mock-bin', 'gh'), `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(process.env.MOCK_LOG, JSON.stringify(args) + '\\n');
if (args[0] === 'api') {
 if (process.env.MOCK_API_FAILURE) process.exit(1);
 if (args[1].includes('/matching-refs/')) {
  if (process.env.MOCK_TAG_SHA) console.log('refs/tags/' + process.env.RELEASE_TAG);
 } else console.log(process.env.MOCK_TAG_SHA);
} else if (args[1] === 'view') process.exit(process.env.MOCK_EXISTING ? 0 : 1);
`, { mode: 0o755 });
	const result = spawnSync('bash', [publisher], {
		cwd: dir, encoding: 'utf8',
		env: { ...process.env, PATH: path.join(dir, 'mock-bin') + path.delimiter + process.env.PATH,
			GH_REPO: 'example/argon', RELEASE_TAG: options.tag || 'v2.0.0', RELEASE_SHA: 'a'.repeat(40),
			MOCK_LOG: log, MOCK_TAG_SHA: options.sha || '', MOCK_EXISTING: options.existing ? '1' : '',
			MOCK_API_FAILURE: options.apiFailure ? '1' : '' }
	});
	const calls = fs.existsSync(log) ? fs.readFileSync(log, 'utf8').trim().split('\n').map(JSON.parse) : [];
	return { dir, result, calls };
}

test('new releases contain both package formats, translations and correct basename checksums', t => {
	const f = fixture(t);
	assert.equal(f.result.status, 0, f.result.stderr);
	const create = f.calls.find(args => args[0] === 'release' && args[1] === 'create');
	assert.ok(create.includes('luci-app-argon-config-2.0.0-r1.apk'));
	assert.ok(create.includes('luci-app-argon-config_2.0.0-r1_all.ipk'));
	assert.ok(create.includes('luci-i18n-argon-config-app-zh-cn-2.0.0-r1.apk'));
	assert.ok(create.includes('SHA256SUMS'));
	assert.equal(create.includes('--draft'), false);
	assert.equal(create[create.indexOf('--target') + 1], 'a'.repeat(40));
	const lines = fs.readFileSync(path.join(f.dir, 'release-assets', 'SHA256SUMS'), 'utf8').trim().split('\n');
	assert.equal(lines.length, 3);
	for (const line of lines) {
		const [digest, name] = line.split('  ');
		assert.equal(name, path.basename(name));
		assert.equal(digest, crypto.createHash('sha256').update(fs.readFileSync(path.join(f.dir, 'packages', name))).digest('hex'));
	}
});

test('an incomplete build cannot create a public release', t => {
	const f = fixture(t, { omitIpk: true });
	assert.notEqual(f.result.status, 0);
	assert.equal(f.calls.some(args => args[0] === 'release'), false);
});

test('manual releases cannot reuse a tag pointing to another source commit', t => {
	const f = fixture(t, { sha: 'b'.repeat(40) });
	assert.notEqual(f.result.status, 0);
	assert.match(f.result.stderr, /different commit/);
	assert.equal(f.calls.some(args => args[0] === 'release'), false);
});

test('API failures stop publication instead of bypassing tag validation', t => {
	const f = fixture(t, { apiFailure: true });
	assert.notEqual(f.result.status, 0);
	assert.equal(f.calls.some(args => args[0] === 'release'), false);
});

test('reruns complete an existing release from the same commit without replacing its notes', t => {
	const f = fixture(t, { sha: 'a'.repeat(40), existing: true });
	assert.equal(f.result.status, 0, f.result.stderr);
	assert.equal(f.calls.some(args => args[1] === 'create'), false);
	assert.ok(f.calls.some(args => args[1] === 'upload' && args.includes('--clobber')));
	const edit = f.calls.find(args => args[1] === 'edit');
	assert.ok(edit.includes('--draft=false'));
	assert.equal(edit.some(arg => arg.startsWith('--notes')), false);
});

test('a release tag must match the source package version', t => {
	const f = fixture(t, { tag: 'v9.0.0' });
	assert.notEqual(f.result.status, 0);
	assert.match(f.result.stderr, /must match/);
	assert.equal(f.calls.length, 0);
});
