const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const logic = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../settings.js'), 'utf8'), logic);
const plain = value => JSON.parse(JSON.stringify(value));

test('saves only overrides, and returning to a default removes an override', () => {
    const defaults = { fontFamily: 'Mononoki Nerd Font', launcherRows: 8 };
    const first = logic.updated({}, defaults, 'launcherRows', 12);
    const second = logic.updated(first, defaults, 'fontFamily', 'Iosevka Nerd Font');
    const resetRows = logic.updated(second, defaults, 'launcherRows', 8);
    assert.deepEqual(plain(first), { launcherRows: 12 });
    assert.deepEqual(plain(resetRows), { fontFamily: 'Iosevka Nerd Font' });
    assert.deepEqual(defaults, { fontFamily: 'Mononoki Nerd Font', launcherRows: 8 });
});

test('round-trips settings including zero durations, zero history and false', () => {
    const overrides = {
        animationPopup: 0, historyLimit: 0, layoutIcons: false,
        profilePic: '', wallpaperFolder: 'Pictures/壁紙', libraryFolder: '/mnt/example/Books', volumeLimit: 125
    };
    assert.deepEqual(plain(logic.decode(logic.encode(overrides))), overrides);
});

test('rejects damaged or incompatible files instead of replacing saved settings', () => {
    for (const document of ['', '{', 'null', '[]', '{}',
        '{"version":2,"overrides":{}}', '{"version":1,"overrides":[]}',
        '{"version":1,"overrides":{"launcherRows":100000}}',
        '{"version":1,"overrides":{"unknown":true}}',
        '{"version":1,"overrides":{"__proto__":{}}}']) {
        assert.throws(() => logic.decode(document));
    }
});

test('rejects invalid types, out-of-range values and unsafe text', () => {
    for (const [key, value] of [
        ['launcherRows', 0], ['launcherRows', 21], ['launcherRows', 2.5], ['launcherRows', '8'],
        ['animationSlide', -1], ['animationTabSlide', 2001], ['animationPopup', NaN],
        ['historyLimit', Infinity], ['notificationTimeout', 999], ['notificationTimeout', 60001],
        ['volumeLimit', 99], ['volumeLimit', 201], ['layoutIcons', 1],
        ['fontFamily', ''], ['fontFamily', ' padded '], ['fontFamily', 'font\nname'],
        ['wallpaperFolder', ''], ['libraryFolder', ''], ['libraryFolder', 1], ['profilePic', null]
    ]) {
        assert.throws(() => logic.validate(key, value), `${key}: ${String(value)}`);
    }
});

test('accepts supported boundary values', () => {
    for (const [key, value] of [
        ['launcherRows', 1], ['launcherRows', 20], ['animationPopup', 0],
        ['animationSlide', 2000], ['historyLimit', 0], ['historyLimit', 2000],
        ['notificationTimeout', 1000], ['notificationTimeout', 60000],
        ['volumeLimit', 100], ['volumeLimit', 200], ['layoutIcons', false]
    ]) {
        assert.equal(logic.validate(key, value), value);
    }
});

test('stores home paths portably and accepts local file picker URLs', () => {
    const home = '/home/example';
    assert.equal(logic.storedPath('Pictures/Wallpapers', home), 'Pictures/Wallpapers');
    assert.equal(logic.storedPath('~/Pictures/a b.png', home), 'Pictures/a b.png');
    assert.equal(logic.storedPath('file:///home/example/Pictures/a%20b%23c.png', home), 'Pictures/a b#c.png');
    assert.equal(logic.storedPath('file://localhost/tmp/a%20b.png', home), '/tmp/a b.png');
    assert.equal(logic.storedPath('/mnt/wallpapers', home), '/mnt/wallpapers');
    assert.equal(logic.storedPath('', home), '');
    assert.throws(() => logic.storedPath('https://example.test/picture.png', home));
    assert.throws(() => logic.storedPath('file://remote/share/picture.png', home));
    assert.throws(() => logic.storedPath('file:///tmp/%broken', home));
});

test('encodes local image URLs without losing spaces, percent signs, hashes or Unicode', () => {
    assert.equal(logic.fileUrl('Pictures/a b#%.png', '/home/example'),
        'file:///home/example/Pictures/a%20b%23%25.png');
    assert.equal(logic.fileUrl('/tmp/壁紙.png', '/home/example'), 'file:///tmp/%E5%A3%81%E7%B4%99.png');
    assert.equal(logic.fileUrl('', '/home/example'), '');
});
