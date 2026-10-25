'use strict';
'require form';
'require fs';
'require rpc';
'require uci';
'require ui';
'require view';

var bgPath = '/www/luci-static/argon/background/';
var mediaPattern = /\.(gif|jpe?g|png|webp|mp4|webm)$/i;
var callSpace = rpc.declare({ object: 'luci.argon_config', method: 'avail', reject: true });
var callRemove = rpc.declare({
	object: 'luci.argon_config', method: 'remove', params: ['filename'], reject: true
});
var callInstall = rpc.declare({
	object: 'luci.argon_config', method: 'install', params: ['tmpfile', 'filename'], reject: true
});

function checkResult(reply) {
	var errors = {
		1: _('Invalid filename.'),
		2: _('Supported formats: GIF, JPEG, PNG, WebP, MP4 and WebM.'),
		3: _('The uploaded file is missing or empty. Please upload it again.'),
		4: _('A file with this name already exists. Rename the file or delete the old one first.'),
		5: _('The operation failed. Check free space and directory permissions.')
	};
	if (!reply || reply.result !== 0)
		throw new Error(errors[reply && reply.result] || _('The operation failed. Please try again.'));
}

function notifyError(error) {
	ui.addNotification(null, E('p', error.message), 'error');
}

function listBackgrounds() {
	return fs.list(bgPath).catch(function(error) {
		if (error.name === 'NotFoundError')
			return [];
		throw error;
	});
}

function validateColor(section, value) {
	return /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i.test(value) || _('Expecting: %s').format(_('valid HEX color value'));
}

function wallpaperSetting(section) {
	var value = uci.get('argon', section, 'online_wallpaper') || 'none';
	var match = /^(unsplash|wallhaven)_(.*)$/.exec(value);
	return match ? { source: match[1], filter: match[2] } : { source: value, filter: '' };
}

function normalizeFilter(value) {
	return String(value || '').split(',').map(function(id) { return id.trim(); }).join(',');
}

function addWallpaperOptions(section) {
	var source = section.taboption('general', form.ListValue, 'online_wallpaper', _('Wallpaper source'));
	source.value('none', _('Local backgrounds (built-in if empty)'));
	source.value('bing', _('Bing'));
	source.value('unsplash', _('Unsplash'));
	source.value('wallhaven', _('Wallhaven'));
	source.description = _('Local backgrounds are selected randomly. Online sources require Internet access.');
	source.default = 'none';
	source.rmempty = false;
	source.cfgvalue = function(id) { return wallpaperSetting(id).source; };
	// A filter can change while the source stays the same.
	source.forcewrite = true;

	var filters = ['unsplash', 'wallhaven'].map(function(provider) {
		var name = provider === 'unsplash' ? 'unsplash_collection' : 'wallhaven_tag';
		var option = section.taboption('general', form.Value, name,
			provider === 'unsplash' ? _('Unsplash collection IDs (optional)') : _('Wallhaven tag ID (optional)'));
		option.depends('online_wallpaper', provider);
		option.retain = true;
		option.description = provider === 'unsplash'
			? _('Enter public collection IDs separated by commas. Leave empty for random photos.')
			: _('Enter one numeric tag ID, not a wallpaper ID. A tag enables the API key and resolution options below.');
		option.cfgvalue = function(id) {
			var setting = wallpaperSetting(id);
			return setting.source === provider ? setting.filter : (uci.get('argon', id, name) || '');
		};
		option.validate = function(id, value) {
			value = normalizeFilter(value);
			return !value || (provider === 'unsplash' ? /^[A-Za-z0-9_-]+(?:,[A-Za-z0-9_-]+)*$/ : /^[1-9][0-9]*$/).test(value)
				|| (provider === 'unsplash' ? _('Use collection IDs separated by commas, without URLs.') : _('Use one positive numeric tag ID.'));
		};
		option.write = function(id, value) { uci.set('argon', id, name, normalizeFilter(value)); };
		return option;
	});
	source.write = function(id, value) {
		var values = filters.map(function(option) { return normalizeFilter(option.formvalue(id)); });
		filters.forEach(function(option, index) {
			if (values[index]) uci.set('argon', id, option.option, values[index]);
			else uci.unset('argon', id, option.option);
		});
		var filter = value === 'unsplash' ? values[0] : value === 'wallhaven' ? values[1] : '';
		uci.set('argon', id, 'online_wallpaper', value + (filter ? '_' + filter : ''));
	};

	var key = section.taboption('general', form.Value, 'use_api_key', _('Wallpaper API key'));
	key.password = true;
	key.retain = true;
	key.depends('online_wallpaper', 'unsplash');
	key.depends({ online_wallpaper: 'wallhaven', wallhaven_tag: /^\s*[1-9][0-9]*\s*$/ });
	key.description = _('Unsplash requires its Access Key. For a Wallhaven tag search, use a Wallhaven API key or leave empty.');
	key.validate = function(id, value) {
		return source.formvalue(id) !== 'unsplash' || !!String(value || '').trim() || _('An Unsplash Access Key is required.');
	};
	var resolution = section.taboption('general', form.Flag, 'use_exact_resolution', _('Require exact resolution for Wallhaven'));
	resolution.depends({ online_wallpaper: 'wallhaven', wallhaven_tag: /^\s*[1-9][0-9]*\s*$/ });
	resolution.default = '1';
	resolution.rmempty = false;
	resolution.retain = true;
	resolution.description = _('For tag searches: require 1920x1080, or disable to allow images at least 1920x1080.');
}

return view.extend({
	load: function() {
		return Promise.all([uci.load('argon'), callSpace(), listBackgrounds()]);
	},

	refreshBackgrounds: function() {
		return Promise.all([callSpace(), listBackgrounds()]).then(L.bind(function(data) {
			this.renderFiles(data[1]);
			this.space.textContent = data[0].avail >= 0
				? _('Available space: %1024.2mB').format(data[0].avail * 1024)
				: _('Available space: unknown');
		}, this));
	},

	handleUpload: function(ev) {
		var tmpfile = '/tmp/argon-config-upload-' + Date.now().toString(16) + Math.random().toString(16).slice(2);
		var uploaded = false;
		return ui.uploadFile(tmpfile).then(function(file) {
			uploaded = true;
			if (!mediaPattern.test(file.name))
				throw new Error(_('Supported formats: GIF, JPEG, PNG, WebP, MP4 and WebM.'));
			return callInstall(tmpfile, file.name).then(checkResult);
		}).then(L.bind(function() {
			ui.addNotification(null, E('p', _('Background uploaded. Select the local wallpaper source and save to use it.')), 'info');
			return this.refreshBackgrounds();
		}, this)).catch(function(error) {
			// Cancelling the LuCI upload dialog does not create a file.
			if (uploaded || error.message !== _('Upload has been cancelled'))
				notifyError(error);
		}).finally(function() {
			return fs.remove(tmpfile).catch(function() {});
		});
	},

	handleDelete: function(file) {
		ui.showModal(_('Delete background'), [
			E('p', _('Delete "%s"? This cannot be undone.').format(file.name)),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')),
				' ',
				E('button', {
					'class': 'btn cbi-button-remove',
					'click': ui.createHandlerFn(this, function() {
						return callRemove(file.name).then(checkResult).then(L.bind(function() {
							ui.hideModal();
							return this.refreshBackgrounds();
						}, this)).catch(notifyError);
					})
				}, _('Delete'))
			])
		]);
	},

	handlePreview: function(file) {
		var url = L.resource('../argon/background/' + encodeURIComponent(file.name)) + '?v=' + file.mtime;
		ui.showModal(file.name, [
			E(/\.(mp4|webm)$/i.test(file.name) ? 'video' : 'img', {
				'src': url, 'alt': file.name, 'controls': true,
				'style': 'display:block;max-width:100%;max-height:65vh;margin:auto'
			}),
			E('div', { 'class': 'right' }, E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Close')))
		]);
	},

	renderFiles: function(files) {
		var rows = files.filter(function(file) {
			return file.type === 'file' && mediaPattern.test(file.name) && file.name.charAt(0) !== '.';
		}).sort(function(a, b) { return a.name.localeCompare(b.name); }).map(L.bind(function(file) {
			return [file.name, new Date(file.mtime * 1000).toLocaleString(),
				'%1024.2mB'.format(file.size), E('div', { 'class': 'nowrap' }, [
					E('button', {
						'class': 'btn cbi-button-action', 'type': 'button',
						'click': ui.createHandlerFn(this, 'handlePreview', file)
					}, _('Preview')), ' ',
					E('button', {
						'class': 'btn cbi-button-remove', 'type': 'button', 'disabled': this.readonly || null,
						'click': ui.createHandlerFn(this, 'handleDelete', file)
					}, _('Delete'))
				])];
		}, this));
		cbi_update_table(this.fileTable, rows, E('em', _('No files found.')));
	},

	render: function(data) {
		var m = new form.Map('argon', _('Argon theme configuration'),
			_('Customize the login page and manage local backgrounds. Changes take effect after Save & Apply.'));
		var s = m.section(form.TypedSection, 'global', _('Theme configuration'));
		s.anonymous = true;
		s.addremove = false;
		s.tab('general', _('General'));
		s.tab('light', _('Light mode'));
		s.tab('dark', _('Dark mode'));

		var o = s.taboption('general', form.ListValue, 'mode', _('Theme mode'));
		o.value('normal', _('Follow system'));
		o.value('light', _('Light mode'));
		o.value('dark', _('Dark mode'));
		o.default = 'normal';
		o.rmempty = false;

		addWallpaperOptions(s);

		['light', 'dark'].forEach(function(tab) {
			var dark = tab === 'dark';
			o = s.taboption(tab, form.Value, dark ? 'dark_primary' : 'primary', _('Primary color'));
			o.default = dark ? '#483d8b' : '#5e72e4';
			o.description = _('Use a HEX color such as #5e72e4 or #fff.');
			o.validate = validateColor;
			o.rmempty = false;
			o = s.taboption(tab, form.Value, dark ? 'transparency_dark' : 'transparency', _('Transparency'));
			o.datatype = 'range(0,1)';
			o.default = '0.5';
			o.description = _('0 is transparent; 1 is opaque.');
			o.rmempty = false;
			o = s.taboption(tab, form.Value, dark ? 'blur_dark' : 'blur', _('Frosted glass radius'));
			o.datatype = 'range(0,100)';
			o.default = '10';
			o.description = _('Blur radius in pixels, from 0 to 100.');
			o.rmempty = false;
		});

		this.readonly = !L.hasViewPermission();
		this.space = E('p');
		this.space.textContent = data[1].avail >= 0
			? _('Available space: %1024.2mB').format(data[1].avail * 1024) : _('Available space: unknown');
		this.fileTable = E('table', { 'class': 'table' }, E('tr', { 'class': 'tr table-titles' },
			[_('Filename'), _('Modified date'), _('Size'), _('Action')].map(function(title) {
				return E('th', { 'class': 'th' }, title);
			})));
		this.renderFiles(data[2]);
		return m.render().then(L.bind(function(node) {
			return E('div', [node, E('div', { 'class': 'cbi-section' }, [
				E('h3', _('Local backgrounds')), this.space,
				E('p', _('Supported formats: GIF, JPEG, PNG, WebP, MP4 and WebM.')),
				E('p', _('Uploads and deletions take effect immediately and do not discard unsaved theme settings.')),
				E('p', [E('button', {
					'type': 'button', 'class': 'btn cbi-button-action', 'disabled': this.readonly || null,
					'click': ui.createHandlerFn(this, 'handleUpload')
				}, _('Upload background')), ' ', E('button', {
					'type': 'button', 'class': 'btn',
					'click': ui.createHandlerFn(this, function() { return this.refreshBackgrounds().catch(notifyError); })
				}, _('Refresh'))]), this.fileTable
			])]);
		}, this));
	}
});
