const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('htdocs/luci-static/resources/view/argon-config-app.js', 'utf8');

function loadView(writable = true) {
	const state = { notifications: [], removed: [], calls: [], options: [], files: [], uploads: [], rows: [], config: {}, values: {} };
	function E(tag, attrs, children) {
		if (arguments.length < 3 && (Array.isArray(attrs) || typeof attrs === 'string' || attrs?.tag)) {
			children = attrs; attrs = {};
		}
		return { tag, attrs: attrs || {}, children, textContent: '' };
	}
	class Map {
		section(type, config) {
			assert.equal(config, 'global');
			return {
				tab() {},
				taboption(tab, type, name) {
					const option = {
						name, option: name, tab, dependencies: [], value() {},
						depends(...args) { this.dependencies.push(args); },
						cfgvalue(id) { return state.config[id]?.[name]; },
						formvalue(id) { return state.values[id]?.[name] ?? this.cfgvalue(id) ?? this.default ?? ''; }
					};
					state.options.push(option);
					return option;
				}
			};
		}
		render() { return Promise.resolve(E('form')); }
	}
	const context = vm.createContext({
		E, console, Date, Promise, Math,
		_: text => text,
		cbi_update_table(table, rows) { state.rows = rows; },
		L: {
			bind: (fn, ctx) => fn.bind(ctx), hasViewPermission: () => writable,
			resource: path => '/luci-static/resources/' + path
		},
		view: { extend: obj => obj },
		form: { Map, TypedSection: 'TypedSection', ListValue: 'ListValue', Value: 'Value', Flag: 'Flag' },
		uci: {
			load: async () => { state.loaded = true; },
			get: (config, id, name) => state.config[id]?.[name],
			set: (config, id, name, value) => { (state.config[id] ||= {})[name] = value; },
			unset: (config, id, name) => { delete (state.config[id] || {})[name]; }
		},
		fs: {
			list: async () => { if (state.listError) throw state.listError; return state.files; },
			remove: async path => state.removed.push(path)
		},
		rpc: { declare: spec => async (...args) => {
			state.calls.push({ method: spec.method, args });
			if (state.rpcError) throw state.rpcError;
			return spec.method === 'avail' ? { avail: 1024 } : { result: state.result ?? 0 };
		} },
		ui: {
			addNotification: (title, content, level) => state.notifications.push({ content, level }),
			uploadFile: async path => { state.uploads.push(path); if (state.uploadError) throw state.uploadError; return state.upload; },
			showModal: (title, children) => { state.modal = { title, children }; },
			hideModal: () => { state.modal = null; },
			createHandlerFn: (ctx, fn, ...args) => (...rest) => (typeof fn === 'string' ? ctx[fn] : fn).apply(ctx, [...args, ...rest])
		}
	});
	vm.runInContext('String.prototype.format = function(...args) { let i=0; return this.replace(/%s|%1024\\.2mB/g, () => String(args[i++])); };', context);
	state.view = vm.runInContext('(function() {\n' + source + '\n})()', context);
	state.render = async () => state.view.render(await state.view.load());
	return state;
}

function buttons(node, out = []) {
	if (!node || typeof node !== 'object') return out;
	if (node.tag === 'button') out.push(node);
	for (const child of Array.isArray(node.children) ? node.children : [node.children]) buttons(child, out);
	return out;
}

test('settings use LuCI footer actions and validate HEX colors', async () => {
	const s = loadView(); const page = await s.render();
	assert.equal(buttons(page).find(b => b.children === 'Upload background').attrs.disabled, null);
	assert.equal(Object.hasOwn(s.view, 'handleSaveApply'), false);
	assert.equal(Object.hasOwn(s.view, 'handleSave'), false);
	assert.equal(Object.hasOwn(s.view, 'handleReset'), false);
	const color = s.options.find(o => o.name === 'primary');
	for (const value of ['#fff', '#A1b2C3']) assert.equal(color.validate('global', value), true);
	for (const value of ['red', '#ffff', '#ffffff;background:red']) assert.notEqual(color.validate('global', value), true);
	assert.equal(s.options.some(o => o.name.startsWith('_')), false);
});

test('missing background directory renders empty, permission errors remain visible', async () => {
	const s = loadView(); s.listError = Object.assign(new Error('missing'), { name: 'NotFoundError' });
	await s.render(); assert.equal(s.rows.length, 0);
	s.listError = new Error('permission denied');
	await assert.rejects(s.view.load(), /permission denied/);
});

test('upload publishes once, refreshes in place and cleans its unique staging file', async () => {
	const s = loadView(); await s.render(); s.upload = { name: '日落 & sky.JPG' };
	await s.view.handleUpload();
	const publish = s.calls.find(c => c.method === 'install');
	assert.match(publish.args[0], /^\/tmp\/argon-config-upload-[0-9a-f]{16,64}$/);
	assert.equal(publish.args[1], s.upload.name);
	assert.equal(s.removed[0], publish.args[0]);
	assert.equal(s.notifications[0].level, 'info');
	await s.view.handleUpload();
	assert.notEqual(s.uploads[0], s.uploads[1]);
});

test('unsupported uploads and backend failures show errors without reporting success', async () => {
	const s = loadView(); await s.render(); s.upload = { name: 'script.html' };
	await s.view.handleUpload();
	assert.equal(s.calls.some(c => c.method === 'install'), false);
	assert.equal(s.notifications[0].level, 'error');
	assert.equal(s.removed.length, 1);
	s.upload = { name: 'sky.png' }; s.result = 4;
	await s.view.handleUpload();
	assert.match(s.notifications[1].content.children, /already exists/);
	assert.equal(s.notifications.every(n => n.level === 'error'), true);
});

test('cancelled upload leaves no error banner', async () => {
	const s = loadView(); s.uploadError = new Error('Upload has been cancelled');
	await s.view.handleUpload();
	assert.equal(s.notifications.length, 0);
});

test('delete requires confirmation and preserves the dialog on failure', async () => {
	const s = loadView(); await s.render();
	s.view.handleDelete({ name: 'sky.png' });
	assert.equal(s.calls.some(c => c.method === 'remove'), false);
	let confirm = buttons({ children: s.modal.children }).find(b => b.children === 'Delete');
	s.result = 5; await confirm.attrs.click();
	assert.ok(s.modal); assert.equal(s.notifications[0].level, 'error');
	s.result = 0; await confirm.attrs.click(); assert.equal(s.modal, null);
});

test('file list filters unsafe entries and previews an encoded media URL', async () => {
	const s = loadView(); await s.render();
	s.view.renderFiles([
		{ name: 'z.mp4', type: 'file', mtime: 1, size: 1 },
		{ name: 'a #1.png', type: 'file', mtime: 2, size: 1 },
		{ name: '.hidden.png', type: 'file' }, { name: 'dir.png', type: 'directory' },
		{ name: 'symlink.png', type: 'link' }, { name: 'x.html', type: 'file' }
	]);
	assert.equal(s.rows.length, 2); assert.equal(s.rows[0][0], 'a #1.png');
	s.view.handlePreview({ name: 'a #1.png', mtime: 2 });
	assert.equal(s.modal.children[0].tag, 'img');
	assert.equal(new URL(s.modal.children[0].attrs.src, 'http://router').pathname, '/luci-static/argon/background/a%20%231.png');
	s.view.handlePreview({ name: 'z.mp4', mtime: 1 });
	assert.equal(s.modal.children[0].tag, 'video');
});

test('read-only users can preview but cannot use upload or delete buttons', async () => {
	const s = loadView(false); const page = await s.render();
	assert.equal(buttons(page).find(b => b.children === 'Upload background').attrs.disabled, true);
	s.view.renderFiles([{ name: 'a.png', type: 'file', mtime: 1, size: 1 }]);
	const row = buttons(s.rows[0][3]);
	assert.equal(row.find(b => b.children === 'Delete').attrs.disabled, true);
	assert.notEqual(row.find(b => b.children === 'Preview').attrs.disabled, true);
});

test('mutating RPC calls belong exclusively to the write ACL', () => {
	const acl = JSON.parse(fs.readFileSync('root/usr/share/rpcd/acl.d/luci-app-argon-config-standalone.json'))['luci-app-argon-config-standalone'];
	assert.deepEqual(acl.read.ubus['luci.argon_config'], ['avail']);
	assert.deepEqual(acl.write.ubus['luci.argon_config'], ['install', 'remove']);
	assert.deepEqual(Object.keys(acl.write.file), ['/tmp/argon-config-upload-*']);
});

test('encoded wallpaper settings load from the actual anonymous section without truncating IDs', async () => {
	const s = loadView(); await s.render();
	const option = name => s.options.find(o => o.name === name);
	s.config.cfg04a19 = { online_wallpaper: 'unsplash_317099,a_b-C', unsplash_collection: 'stale' };
	assert.equal(option('online_wallpaper').cfgvalue('cfg04a19'), 'unsplash');
	assert.equal(option('unsplash_collection').cfgvalue('cfg04a19'), '317099,a_b-C');
	s.config.cfg04a19.online_wallpaper = 'wallhaven_37';
	assert.equal(option('online_wallpaper').cfgvalue('cfg04a19'), 'wallhaven');
	assert.equal(option('wallhaven_tag').cfgvalue('cfg04a19'), '37');
});

test('changing only a collection filter updates the theme setting and clearing it selects random photos', async () => {
	const s = loadView(); await s.render();
	const source = s.options.find(o => o.name === 'online_wallpaper');
	s.config.cfg0123 = { online_wallpaper: 'unsplash_317099' };
	s.values.cfg0123 = { online_wallpaper: 'unsplash', unsplash_collection: ' 123 , a_b-C ', wallhaven_tag: '' };
	assert.equal(source.forcewrite, true);
	source.write('cfg0123', 'unsplash');
	assert.equal(s.config.cfg0123.online_wallpaper, 'unsplash_123,a_b-C');
	assert.equal(s.config.cfg0123.unsplash_collection, '123,a_b-C');
	s.values.cfg0123.unsplash_collection = '';
	source.write('cfg0123', 'unsplash');
	assert.equal(s.config.cfg0123.online_wallpaper, 'unsplash');
	assert.equal(s.config.cfg0123.unsplash_collection, undefined);
});

test('switching sources preserves each provider filter, including a legacy encoded collection', async () => {
	const s = loadView(); await s.render();
	const source = s.options.find(o => o.name === 'online_wallpaper');
	s.config.cfg0123 = { online_wallpaper: 'unsplash_317099', wallhaven_tag: '37' };
	source.write('cfg0123', 'bing');
	assert.equal(s.config.cfg0123.online_wallpaper, 'bing');
	assert.equal(s.config.cfg0123.unsplash_collection, '317099');
	assert.equal(s.config.cfg0123.wallhaven_tag, '37');
	source.write('cfg0123', 'wallhaven');
	assert.equal(s.config.cfg0123.online_wallpaper, 'wallhaven_37');
});

test('filter validation rejects URLs, query injection and wallpaper IDs in the tag field', async () => {
	const s = loadView(); await s.render();
	const collections = s.options.find(o => o.name === 'unsplash_collection');
	const tag = s.options.find(o => o.name === 'wallhaven_tag');
	for (const value of ['', '317099', '123, a_b-C']) assert.equal(collections.validate('cfg', value), true);
	for (const value of ['https://unsplash.com/collections/123', '1&client_id=x', '1,,2', '123/456'])
		assert.notEqual(collections.validate('cfg', value), true);
	for (const value of ['', '37', '12345']) assert.equal(tag.validate('cfg', value), true);
	for (const value of ['0', 'yqg6r7', '37,38', '-1', '1&apikey=x']) assert.notEqual(tag.validate('cfg', value), true);
});

test('API keys are required for Unsplash and optional for Wallhaven tag searches', async () => {
	const s = loadView(); await s.render();
	const key = s.options.find(o => o.name === 'use_api_key');
	s.values.cfg = { online_wallpaper: 'unsplash' };
	assert.notEqual(key.validate('cfg', ''), true);
	assert.notEqual(key.validate('cfg', '  '), true);
	assert.equal(key.validate('cfg', 'test-access-key'), true);
	s.values.cfg.online_wallpaper = 'wallhaven';
	assert.equal(key.validate('cfg', ''), true);
	assert.equal(key.password, true);
	assert.equal(key.retain, true);
	const resolution = s.options.find(o => o.name === 'use_exact_resolution');
	assert.equal(resolution.default, '1');
	const condition = resolution.dependencies[0][0];
	assert.equal(condition.online_wallpaper, 'wallhaven');
	assert.equal(condition.wallhaven_tag.test('37'), true);
	assert.equal(condition.wallhaven_tag.test(' 37 '), true);
	assert.equal(condition.wallhaven_tag.test(''), false);
});
