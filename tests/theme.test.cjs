// Run with: node --test tests/theme.test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { test } = require('node:test');
const vm = require('node:vm');
const script = path.resolve(__dirname, '../scripts/set-wallpaper.sh');

function fixture(t) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'quickshell-theme-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const bin = path.join(dir, 'bin');
    fs.mkdirSync(bin);
    const image = path.join(dir, 'wallpaper with spaces.png');
    fs.writeFileSync(image, '');
    const log = path.join(dir, 'calls.jsonl');
    for (const command of ['awww', 'wal', 'hyprctl', 'python3', 'pgrep', 'pkill']) {
        fs.writeFileSync(path.join(bin, command), `#!${process.execPath}
const fs = require('node:fs');
const command = ${JSON.stringify(command)};
if (command === 'pgrep') process.exit(0);
if (command === 'python3' && process.argv[2] === '-c') console.log(process.env.TEST_IMAGE);
else fs.appendFileSync(process.env.TEST_LOG, JSON.stringify([command, ...process.argv.slice(2)]) + '\\n');
if (command === process.env.TEST_FAIL ||
    (command === 'python3' && process.argv[2] !== '-c' && process.env.TEST_FAIL === 'palette')) process.exit(1);
`, { mode: 0o755 });
    }
    const state = path.join(dir, 'state');
    const modeFile = path.join(state, 'quickshell/theme-mode');
    return {
        image,
        palette: path.join(state, 'quickshell/palette.json'),
        mode: () => fs.readFileSync(modeFile, 'utf8').trim(),
        run(args, fail = '') {
            fs.writeFileSync(log, '');
            const result = spawnSync('bash', [script, ...args], {
                encoding: 'utf8',
                env: { ...process.env, PATH: bin + ':' + process.env.PATH,
                    XDG_STATE_HOME: state, TEST_IMAGE: image, TEST_LOG: log, TEST_FAIL: fail }
            });
            const calls = fs.readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse);
            return { ...result, calls };
        }
    };
}

test('theme selection persists and subsequent wallpapers use that mode', t => {
    const f = fixture(t);
    let result = f.run([f.image]);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(result.calls, [
        ['awww', 'img', f.image, '--transition-type', 'any'],
        ['python3', path.resolve(__dirname, '../scripts/palette.py'), f.image, 'dark'],
        ['wal', '-n', '-f', f.palette], ['pkill', '-USR1', '-u', String(process.getuid()), '-x', 'kitty'], ['hyprctl', 'reload']
    ]);
    assert.equal(f.mode(), 'dark');

    result = f.run(['--theme', 'light']);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(result.calls, [
        ['python3', path.resolve(__dirname, '../scripts/palette.py'), f.image, 'light'],
        ['wal', '-n', '-f', f.palette], ['pkill', '-USR1', '-u', String(process.getuid()), '-x', 'kitty'], ['hyprctl', 'reload']
    ]);
    assert.equal(f.mode(), 'light');
    result = f.run([f.image]);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.calls.find(call => call[0] === 'python3').at(-1), 'light');

    result = f.run(['--theme', 'dark']);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(f.mode(), 'dark');
    assert.ok(!result.calls.some(call => call[0] === 'awww'));
    result = f.run([f.image]);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.calls.find(call => call[0] === 'python3').at(-1), 'dark');
});

test('failed or invalid theme requests preserve the saved mode', t => {
    const f = fixture(t);
    assert.equal(f.run(['--theme', 'dark']).status, 0);
    for (const fail of ['wal', 'python3', 'palette']) {
        const result = f.run(['--theme', 'light'], fail);
        assert.notEqual(result.status, 0);
        assert.equal(f.mode(), 'dark');
        assert.ok(!result.calls.some(call => call[0] === 'hyprctl'));
        assert.ok(!result.calls.some(call => call[0] === 'pkill'));
    }
    for (const args of [['--theme', 'invalid'], ['--theme'], ['/missing/wallpaper.png']]) {
        const result = f.run(args);
        assert.notEqual(result.status, 0);
        assert.deepEqual(result.calls, []);
        assert.equal(f.mode(), 'dark');
    }
});

test('launcher filters theme choices and marks the active palette', () => {
    const source = fs.readFileSync(path.join(__dirname, '../AppLauncher.qml'), 'utf8');
    const context = vm.createContext({
        parsedCommand: { word: 'theme', filter: '' },
        activeCommand: { name: 'theme' }, keybindsMode: false, Colors: { isLight: false }
    });
    for (const name of ['fuzzyScore', 'buildCommandEntries']) {
        vm.runInContext(source.match(new RegExp('    function ' + name + '\\([^]*?\\n    }'))[0], context);
    }
    const entries = () => JSON.parse(JSON.stringify(context.buildCommandEntries()));
    assert.deepEqual(entries().map(e => [e.name, e.comment]), [['Dark', 'Active'], ['Light', '']]);
    context.Colors.isLight = true;
    assert.deepEqual(entries().map(e => [e.name, e.comment]), [['Dark', ''], ['Light', 'Active']]);
    context.parsedCommand.filter = ' LIGHT ';
    assert.deepEqual(entries().map(e => e.mode), ['light']);
    context.parsedCommand.filter = 'unknown';
    assert.deepEqual(entries(), []);
});

test('theme and wallpaper actions use the same script with separate arguments', () => {
    const source = fs.readFileSync(path.join(__dirname, '../AppLauncher.qml'), 'utf8');
    let starts = 0, closes = 0;
    const context = vm.createContext({
        keybindsMode: false, commandMode: true, selectedIndex: 0,
        results: [{ kind: 'theme', mode: 'light' }],
        Quickshell: { env: () => '/example' },
        wallpaperProc: { startDetached: () => starts++ },
        launcher: { closeRequested: () => closes++ }
    });
    vm.runInContext(source.match(/    function executeSelected\([^]*?\n    }/)[0], context);
    context.executeSelected();
    assert.deepEqual(Array.from(context.wallpaperProc.command),
        ['bash', '/example/.config/quickshell/scripts/set-wallpaper.sh', '--theme', 'light']);
    context.results = [{ kind: 'wallpaper', filePath: '/pictures/a wallpaper $(literal).png' }];
    context.executeSelected();
    assert.deepEqual(Array.from(context.wallpaperProc.command),
        ['bash', '/example/.config/quickshell/scripts/set-wallpaper.sh', context.results[0].filePath]);
    assert.equal(starts, 2);
    assert.equal(closes, 2);
});
