// Run with: node --test tests/hosts.test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const { once } = require('node:events');
const { test } = require('node:test');
const vm = require('node:vm');

const script = path.resolve(__dirname, '../scripts/ssh-host.sh');
// Fictional fixtures. Tests never load the user's ignored secrets.js.
const hosts = [
    { id: 'example-shell', name: 'Example server', type: 'ssh', destination: 'operator@shell.example.test' },
    { id: 'example-status', name: 'Example status', type: 'ssh', destination: 'operator@status.example.test', startupCommand: '~/padd.sh' },
    { id: 'example-web', name: 'Example dashboard', type: 'web', url: 'http://dashboard.example.test/admin/' }
];

function menuFixture(privateSettings = { hosts }) {
    const source = fs.readFileSync(path.join(__dirname, '../Bar/HostMenu.qml'), 'utf8');
    const calls = [], urls = [];
    let closes = 0;
    const context = vm.createContext({
        Config: { hostMenu: { terminalWidth: 1000, terminalHeight: 650 },
            frame: { thick: 64, thin: 8 }, gap: { md: 12, xxl: 28 } },
        Secrets: privateSettings,
        Hyprland: { toplevels: { values: [] }, dispatch: command => calls.push(command) },
        Qt: { openUrlExternally: url => { urls.push(url); return true; } },
        Quickshell: { shellDir: path.resolve(__dirname, '..') },
        hostMenu: { width: 1920, height: 1080 },
        launchProc: { running: false }, pendingHostId: '', errorText: '', selectedIndex: 0,
        closeRequested: () => closes++
    });
    const binding = source.match(/^    readonly property var hosts: (.+)$/m);
    assert.ok(binding, 'Missing private host list binding');
    context.hostMenu.hosts = vm.runInContext(binding[1], context);
    for (const name of ['existingTerminal', 'chooseHost', 'moveSelection']) {
        const fn = source.match(new RegExp('    function ' + name + '\\([^]*?\\n    }'));
        assert.ok(fn, `Missing ${name}`);
        vm.runInContext(fn[0], context);
    }
    return { context, calls, urls, closes: () => closes };
}

function scriptFixture(t) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'quickshell-ssh-host-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const bin = path.join(dir, 'bin');
    fs.mkdirSync(bin);
    const log = path.join(dir, 'calls.jsonl');
    const mock = String.raw`#!${process.execPath}
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const command = path.basename(process.argv[1]);
const args = process.argv.slice(2);
fs.appendFileSync(process.env.SSH_HOST_TEST_LOG, JSON.stringify([command, ...args]) + '\n');
if (command === 'ssh') {
    if (process.env.SSH_HOST_TEST_STATUS !== '0') fs.writeSync(2, 'Mock SSH connection failed\n');
    process.exit(Number(process.env.SSH_HOST_TEST_STATUS || 0));
}
if (command === 'hyprctl') {
    if (process.env.SSH_HOST_TEST_HYPR_STATUS) process.exit(Number(process.env.SSH_HOST_TEST_HYPR_STATUS));
    if (process.env.SSH_HOST_TEST_HYPR_REPLY) {
        fs.writeSync(1, process.env.SSH_HOST_TEST_HYPR_REPLY + '\n');
        process.exit(0);
    }
    const match = args[1].match(/^hl\.exec_cmd\(\[(=+)\[([\s\S]*?)\]\1\], \{float=true, size=\{(\d+),(\d+)\}, move=\{(\d+),"monitor_h-window_h-(\d+)"\}\}\)$/);
    if (!match) { console.error('Invalid Lua launch expression'); process.exit(2); }
    const result = spawnSync('sh', ['-c', match[2]], { env: process.env, encoding: 'utf8' });
    if (result.status !== 0) { console.error(result.stderr); process.exit(3); }
    fs.writeSync(1, 'ok\n');
}
`;
    for (const command of ['ssh', 'hyprctl', 'kitty'])
        fs.writeFileSync(path.join(bin, command), mock, { mode: 0o755 });
    const env = { ...process.env, PATH: bin + ':' + process.env.PATH,
        SSH_HOST_TEST_LOG: log, SSH_HOST_TEST_STATUS: '0' };
    // These Node executables stand in for regular commands, not test workers.
    delete env.NODE_TEST_CONTEXT;
    return {
        dir, env,
        calls() {
            return fs.readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse);
        },
        run(args, extra = {}) {
            return spawnSync('bash', [script, ...args], {
                env: { ...env, ...extra }, encoding: 'utf8', input: '\n', timeout: 3000
            });
        }
    };
}

test('the public template starts with no hosts and public config has no host definitions', () => {
    const example = vm.createContext({});
    vm.runInContext(fs.readFileSync(path.join(__dirname, '../secrets.js.example'), 'utf8'), example);
    assert.deepEqual(JSON.parse(vm.runInContext('JSON.stringify(hosts)', example)), []);
    const config = vm.createContext({});
    vm.runInContext(fs.readFileSync(path.join(__dirname, '../config.js'), 'utf8'), config);
    assert.equal(vm.runInContext('typeof hosts', config), 'undefined');
});

test('the menu reads hosts from private settings', () => {
    const { context } = menuFixture();
    assert.equal(context.hostMenu.hosts, hosts);
});

test('empty and older private settings show an empty menu without breaking selection', () => {
    for (const settings of [{}, { hosts: [] }]) {
        const { context } = menuFixture(settings);
        assert.equal(context.hostMenu.hosts.length, 0);
        context.moveSelection(1);
        assert.equal(context.selectedIndex, 0);
    }
});

test('an SSH selection launches beside the sidebar with the requested size', () => {
    const { context } = menuFixture();
    context.chooseHost(hosts[0]);
    assert.deepEqual(Array.from(context.launchProc.command), [
        'bash', script, 'example-shell', 'Example server', 'operator@shell.example.test',
        '1000', '650', '76', '20'
    ]);
    assert.equal(context.launchProc.running, true);
});

test('SSH dimensions fit a smaller output without a font override', () => {
    const { context } = menuFixture();
    context.hostMenu = { width: 720, height: 480 };
    context.chooseHost(hosts[0]);
    assert.deepEqual(Array.from(context.launchProc.command).slice(-4), ['600', '408', '76', '20']);
});

test('SSH placement follows the configured sidebar, frame, and gap sizes', () => {
    const { context } = menuFixture();
    context.Config.frame = { thick: 80, thin: 10 };
    context.Config.gap.md = 16;
    context.chooseHost(hosts[0]);
    assert.deepEqual(Array.from(context.launchProc.command).slice(-2), ['96', '26']);
});

test('a terminal on another workspace is focused instead of opening a second session', () => {
    const { context, calls, closes } = menuFixture();
    context.Hyprland.toplevels.values = [{
        wayland: { appId: 'fuchi-ssh-example-shell' },
        lastIpcObject: { address: '0x1234' }, workspace: { active: false }
    }];
    context.pendingHostId = hosts[0].id;
    context.chooseHost(hosts[0]);
    assert.deepEqual(calls, ['hl.dsp.focus({window="address:0x1234"})']);
    assert.equal(context.launchProc.running, false);
    assert.equal(closes(), 1);
});

test('an SSH startup entry launches separately and reuses only its own terminal', () => {
    const { context, calls } = menuFixture();
    const statusHost = hosts.find(host => host.id === 'example-status');
    context.Hyprland.toplevels.values = [{
        wayland: { appId: 'fuchi-ssh-example-shell' },
        lastIpcObject: { address: '0x1234' }
    }];
    context.chooseHost(statusHost);
    assert.deepEqual(Array.from(context.launchProc.command), [
        'bash', script, 'example-status', 'Example status', 'operator@status.example.test',
        '1000', '650', '76', '20', '~/padd.sh'
    ]);
    assert.equal(context.launchProc.running, true);
    assert.deepEqual(calls, []);

    context.launchProc.running = false;
    context.Hyprland.toplevels.values.push({
        wayland: { appId: 'fuchi-ssh-example-status' },
        lastIpcObject: { address: '0x5678' }, workspace: { active: false }
    });
    context.chooseHost(statusHost);
    assert.deepEqual(calls, ['hl.dsp.focus({window="address:0x5678"})']);
    assert.equal(context.launchProc.running, false);
});

test('XWayland class matching also reuses the correct terminal', () => {
    const { context, calls } = menuFixture();
    context.Hyprland.toplevels.values = [
        { wayland: { appId: 'kitty' }, lastIpcObject: { address: '0x1000' } },
        { wayland: null, lastIpcObject: { class: 'fuchi-ssh-example-shell', address: '0x2000' } }
    ];
    context.chooseHost(hosts[0]);
    assert.deepEqual(calls, ['hl.dsp.focus({window="address:0x2000"})']);
    assert.equal(context.launchProc.running, false);
});

test('repeated selection while a terminal is starting does not launch again', () => {
    const { context } = menuFixture();
    context.pendingHostId = hosts[0].id;
    context.chooseHost(hosts[0]);
    assert.equal(context.launchProc.running, false);
    assert.equal(context.launchProc.command, undefined);
});

test('the Example dashboard entry opens the browser and reports a failed browser request', () => {
    const { context, urls, closes } = menuFixture();
    const dashboard = hosts.find(host => host.id === 'example-web');
    context.chooseHost(dashboard);
    assert.deepEqual(urls, ['http://dashboard.example.test/admin/']);
    assert.equal(closes(), 1);
    assert.equal(context.launchProc.running, false);
    context.Qt.openUrlExternally = () => false;
    context.chooseHost(dashboard);
    assert.match(context.errorText, /default browser/);
    assert.equal(closes(), 1);
});

test('keyboard selection wraps and handles an empty host list', () => {
    const { context } = menuFixture();
    context.moveSelection(-1);
    assert.equal(context.selectedIndex, hosts.length - 1);
    context.moveSelection(1);
    assert.equal(context.selectedIndex, 0);
    context.hostMenu.hosts = [];
    context.moveSelection(1);
    assert.equal(context.selectedIndex, 0);
});

test('the launcher applies floating rules and passes quoted arguments literally', t => {
    const f = scriptFixture(t);
    const sentinel = path.join(f.dir, 'should-not-exist');
    const name = `Node's stats ]=] ]==] $(touch ${sentinel})\nOther line`;
    const destination = 'operator@host; echo unexpected';
    const result = f.run(['example-node', name, destination, '1000', '650', '76', '20']);
    assert.equal(result.status, 0, result.stderr);
    const calls = f.calls();
    assert.deepEqual(calls.find(call => call[0] === 'kitty'), [
        'kitty', '--class', 'fuchi-ssh-example-node', '--title', name,
        '-o', 'remember_window_size=no', '-o', 'initial_window_width=1000',
        '-o', 'initial_window_height=650', 'bash', script, '--session', destination
    ]);
    assert.match(calls[0][2], /float=true, size=\{1000,650\}, move=\{76,"monitor_h-window_h-20"\}/);
    assert.equal(fs.existsSync(sentinel), false);
});

test('a menu loaded before the placement update can still launch a terminal', t => {
    const f = scriptFixture(t);
    const result = f.run(['pi', 'Example server', 'operator@host', '1000', '650']);
    assert.equal(result.status, 0, result.stderr);
    const calls = f.calls();
    assert.match(calls[0][2], /move=\{76,"monitor_h-window_h-20"\}/);
    assert.ok(calls.some(call => call[0] === 'kitty'));
});

test('the startup command reaches Kitty literally without running on this computer', t => {
    const f = scriptFixture(t);
    const sentinel = path.join(f.dir, 'should-not-exist');
    const startup = `~/padd.sh --label "Node's stats"; touch ${sentinel}\n# ]=]`;
    const result = f.run(['example-status', 'Example status', 'operator@host', '1000', '650', '76', '20', startup]);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(f.calls().find(call => call[0] === 'kitty').slice(-4), [
        script, '--session', 'operator@host', startup
    ]);
    assert.equal(fs.existsSync(sentinel), false);
});

test('the launcher rejects invalid IDs, geometry, and compositor failures', t => {
    const f = scriptFixture(t);
    for (const args of [[], ['pi', 'Pi', 'operator@host', '1000', '650', '76'],
        ['bad id', 'Pi', 'operator@host', '1000', '650', '76', '20'],
        ['pi', 'Pi', 'operator@host', '-1', '650', '76', '20'],
        ['pi', 'Pi', 'operator@host', '1000;os.exit()', '650', '76', '20'],
        ['pi', 'Pi', 'operator@host', '1000', '650', '-1', '20'],
        ['pi', 'Pi', 'operator@host', '1000', '650', '76', '20\"};os.exit()']])
        assert.equal(f.run(args).status, 2);
    assert.equal(f.run(['pi', 'Pi', 'operator@host', '1000', '650', '76', '20'],
        { SSH_HOST_TEST_HYPR_STATUS: '3' }).status, 3);
    const error = f.run(['pi', 'Pi', 'operator@host', '1000', '650', '76', '20'],
        { SSH_HOST_TEST_HYPR_REPLY: 'Error evaluating Lua' });
    assert.equal(error.status, 1);
    assert.match(error.stderr, /Error evaluating Lua/);
});

test('normal SSH logout exits immediately and retains standard SSH authentication', t => {
    const f = scriptFixture(t);
    const result = f.run(['--session', 'operator@shell.example.test']);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stderr, '');
    assert.deepEqual(f.calls(), [['ssh', '-o', 'ConnectTimeout=10', '--', 'operator@shell.example.test']]);
});

test('PADD requests a remote terminal and leaves home expansion to the Pi', t => {
    const f = scriptFixture(t);
    const result = f.run(['--session', 'operator@status.example.test', '~/padd.sh']);
    assert.equal(result.status, 0, result.stderr);
    const [call] = f.calls();
    assert.deepEqual(call.slice(0, -1), ['ssh', '-t', '-o', 'ConnectTimeout=10', '--', 'operator@status.example.test']);
    assert.match(call.at(-1), /\n~\/padd\.sh\n/);
    assert.ok(call.at(-1).includes('exec "${SHELL:-/bin/sh}" -l'));
});

test('a finished, failed, or missing startup program leads to the remote login shell', t => {
    for (const status of [0, 7, null]) {
        const f = scriptFixture(t);
        assert.equal(f.run(['--session', 'operator@host', '~/padd.sh']).status, 0);
        const remoteCommand = f.calls()[0].at(-1);
        const remoteHome = path.join(f.dir, 'remote-home');
        fs.mkdirSync(remoteHome);
        if (status !== null)
            fs.writeFileSync(path.join(remoteHome, 'padd.sh'),
                `#!/bin/sh\nprintf 'PADD_STARTED\\n'\nexit ${status}\n`, { mode: 0o755 });
        const shell = path.join(f.dir, 'login-shell');
        fs.writeFileSync(shell, '#!/bin/sh\nprintf "LOGIN_PROMPT %s\\n" "$1"\n', { mode: 0o755 });
        for (const remoteShell of ['sh', 'bash']) {
            const result = spawnSync(remoteShell, ['-c', remoteCommand], {
                env: { ...process.env, HOME: remoteHome, SHELL: shell },
                encoding: 'utf8', timeout: 3000
            });
            assert.equal(result.status, 0, result.stderr);
            assert.match(result.stdout, /LOGIN_PROMPT -l/);
            if (status !== null)
                assert.match(result.stdout, /PADD_STARTED[\s\S]*LOGIN_PROMPT/);
            else
                assert.match(result.stderr, /padd\.sh.*(?:not found|No such file)/);
        }
    }
});

test('Ctrl+C stops the startup program and still opens the remote shell', { timeout: 5000 }, async t => {
    const f = scriptFixture(t);
    assert.equal(f.run(['--session', 'operator@host', '~/padd.sh']).status, 0);
    const remoteCommand = f.calls()[0].at(-1);
    fs.writeFileSync(path.join(f.dir, 'padd.sh'),
        '#!/bin/sh\nprintf "PADD_STARTED\\n"\nsleep 30\n', { mode: 0o755 });
    const shell = path.join(f.dir, 'login-shell');
    fs.writeFileSync(shell, '#!/bin/sh\nprintf "LOGIN_PROMPT\\n"\n', { mode: 0o755 });
    const child = spawn('sh', ['-c', remoteCommand], {
        env: { ...process.env, HOME: f.dir, SHELL: shell },
        detached: true, stdio: ['ignore', 'pipe', 'pipe']
    });
    t.after(() => { if (child.exitCode === null && child.signalCode === null) process.kill(-child.pid, 'SIGKILL'); });
    const closed = once(child, 'close');
    let stdout = '';
    await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('Startup program did not start')), 3000);
        child.stdout.on('data', data => {
            stdout += data;
            if (stdout.includes('PADD_STARTED')) { clearTimeout(timer); resolve(); }
        });
        child.once('error', error => { clearTimeout(timer); reject(error); });
    });
    process.kill(-child.pid, 'SIGINT');
    const [code] = await closed;
    assert.equal(code, 0);
    assert.match(stdout, /PADD_STARTED[\s\S]*LOGIN_PROMPT/);
});

test('a failed SSH session preserves its error and waits for Enter before closing', async t => {
    const f = scriptFixture(t);
    const child = spawn('bash', [script, '--session', 'operator@shell.example.test'], {
        env: { ...f.env, SSH_HOST_TEST_STATUS: '255' }, stdio: ['pipe', 'pipe', 'pipe']
    });
    t.after(() => { if (child.exitCode === null) child.kill(); });
    let stderr = '';
    await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('No failure prompt received')), 3000);
        child.stderr.on('data', data => {
            stderr += data;
            if (stderr.includes('Press Enter')) { clearTimeout(timer); resolve(); }
        });
        child.once('error', error => { clearTimeout(timer); reject(error); });
    });
    assert.equal(child.exitCode, null);
    assert.match(stderr, /Mock SSH connection failed/);
    assert.match(stderr, /exit status 255/);
    const closed = once(child, 'close');
    child.stdin.end('\n');
    const [code] = await closed;
    assert.equal(code, 255);
});
