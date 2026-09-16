// Run with: node tests/keybinds.test.cjs
// These tests cover data behavior without starting Quickshell or Hyprland.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { test } = require('node:test');
// QML imports plain scripts rather than CommonJS modules. Load the same source
// into a separate JS context so production code needs no Node-specific exports.
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(require('node:path').join(__dirname, '../keybinds.js'), 'utf8'), context);
// Normalize objects from the VM before strict comparisons across contexts.
const model = (bindings, filter = '') => JSON.parse(JSON.stringify(context.buildModel(bindings, filter)));
// Match the description format emitted by bindInfo() in hyprland.lua.
const bind = (key, action, modmask = 8, mod = 'ALT', category = 'Workspaces', flags = {}) => ({
    key, modmask, description: `qsbind|${category}|${mod}|${action}`, ...flags
});

test('uses Mod only on annotated shortcuts and follows a changed main modifier', () => {
    const result = model([
        bind('P', 'Launcher', 64, 'SUPER', 'Apps and shell'),
        bind('D', 'Dictation', 64, '', 'Dictation'),
        bind('g', 'Reset gaps', 73, 'SUPER', 'Gaps')
    ]);
    assert.equal(result.modLabel, 'Mod = Super');
    assert.equal(result.rows[0].shortcut, 'Mod + P');
    assert.equal(result.rows.find(r => r.category === 'Dictation').shortcut, 'Super + D');
    assert.equal(result.rows.find(r => r.category === 'Gaps').shortcut, 'Mod + Alt + Shift + G');
});

test('condenses workspace families without mixing movement and switching', () => {
    const bindings = [];
    for (let i = 1; i <= 8; i++) {
        bindings.push(bind(String(i), `Switch to workspace ${i}`));
        bindings.push(bind(String(i), `Move window to workspace ${i}`, 9));
    }
    const result = model(bindings);
    assert.equal(result.bindingCount, 16);
    assert.deepEqual(result.rows.map(r => r.shortcut), ['Mod + 1–8', 'Mod + Shift + 1–8']);
    assert.equal(result.rows[1].action, 'Move window to workspace 1–8');
});

test('does not hide missing, remapped, release, or submap workspace bindings', () => {
    const result = model([
        bind('1', 'Switch to workspace 1'), bind('3', 'Switch to workspace 3'),
        bind('4', 'Switch to workspace 4', 8, 'ALT', 'Workspaces', { release: true }),
        bind('5', 'Switch to workspace 5', 8, 'ALT', 'Workspaces', { submap: 'resize' }),
        bind('6', 'Switch to workspace 7')
    ]);
    assert.equal(result.rows.length, 5);
    assert.equal(result.rows[2].note, 'On release');
    assert.equal(result.rows[3].note, 'Submap: resize');
});

test('keeps press and release bindings separate and formats mouse/media keys', () => {
    const result = model([
        bind('D', 'Hold to dictate', 64, '', 'Dictation'),
        bind('D', 'Release to transcribe', 64, '', 'Dictation', { release: true }),
        bind('mouse:272', 'Move window', 8, 'ALT', 'Windows'),
        bind('XF86AudioRaiseVolume', 'Increase volume', 0, '', 'Media and brightness', { repeat: true, locked: true })
    ]);
    assert.equal(result.rows.length, 4);
    assert.equal(result.rows[0].shortcut, 'Mod + Left mouse drag');
    assert.equal(result.rows[2].note, 'On release');
    assert.equal(result.rows[3].shortcut, 'Volume up');
    assert.equal(result.rows[3].note, 'Hold to repeat · Works while locked');
});

test('shows unannotated and unknown categories without losing bindings', () => {
    const result = model([
        { key: 'x', modmask: 8, dispatcher: '__lua', arg: '123' },
        { key: 'y', modmask: 4, description: 'Custom action' },
        bind('z', 'A new action', 8, 'ALT', 'Custom')
    ]);
    assert.equal(result.rows.length, 3);
    assert.equal(result.rows[0].category, 'Other');
    assert.equal(result.rows[0].shortcut, 'Alt + X');
    assert.equal(result.rows[0].action, 'Unlabelled Lua action');
    assert.equal(result.rows[1].action, 'Custom action');
    assert.equal(result.rows[2].category, 'Custom');
});

test('handles empty data and rejects invalid responses', () => {
    assert.equal(model([]).rows.length, 0);
    assert.equal(model([]).modLabel, 'Mod not specified');
    assert.throws(() => model({ error: 'unavailable' }), /Expected a list/);
});

test('filters actions, categories and physical or aliased key combinations', () => {
    const bindings = [
        bind('C', 'Close window', 9, 'ALT', 'Windows'),
        bind('P', 'Open launcher', 8, 'ALT', 'Apps and shell'),
        bind('XF86AudioRaiseVolume', 'Increase volume', 0, '', 'Media and brightness')
    ];
    for (const query of ['window', '  WINDOWS  ', 'close shift', 'Mod + Shift + C', 'alt shift c']) {
        assert.deepEqual(model(bindings, query).rows.map(r => r.action), ['Close window']);
    }
    assert.equal(model(bindings, 'media volume').rows[0].shortcut, 'Volume up');
    assert.equal(model(bindings, 'XF86AudioRaiseVolume').rows.length, 1);
    assert.equal(model(bindings, 'window launcher').rows.length, 0);
});

test('filters individual workspaces before condensing ranges and keeps the Mod header', () => {
    const bindings = Array.from({ length: 8 }, (_, i) => bind(String(i + 1), `Switch to workspace ${i + 1}`));
    const result = model(bindings, 'workspace 4');
    assert.equal(result.rows.length, 1);
    assert.equal(result.rows[0].shortcut, 'Mod + 4');
    assert.equal(result.bindingCount, 8);
    const empty = model(bindings, 'missing action');
    assert.equal(empty.rows.length, 0);
    assert.equal(empty.modLabel, 'Mod = Alt');
    assert.equal(model(bindings, '  ').rows[0].shortcut, 'Mod + 1–8');
});

test('keeps the config order within each category', () => {
    const result = model([
        bind('D', 'Press', 64, '', 'Dictation'),
        bind('P', 'Launcher', 8, 'ALT', 'Apps and shell'),
        bind('D', 'Release', 64, '', 'Dictation', { release: true })
    ]);
    assert.deepEqual(result.rows.map(r => r.action), ['Launcher', 'Press', 'Release']);
});
