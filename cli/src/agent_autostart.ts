import { access, mkdir, rm, writeFile } from 'node:fs/promises';
import { execFile as execFileCallback } from 'node:child_process';
import { homedir, platform, userInfo } from 'node:os';
import { dirname, join } from 'node:path';
import { promisify } from 'node:util';

const execFile = promisify(execFileCallback);
const taskName = 'Float Agent';
const launchAgentName = 'com.dayhawk.float.agent.plist';
const systemdServiceName = 'float-agent.service';

export type AutoStartStatus = {
  platform: string;
  installed: boolean;
  location: string;
};

function launchCommand(): { node: string; entry: string } {
  const entry = process.argv[1];
  if (!entry) throw new Error('Could not determine the Float CLI entry point.');
  return { node: process.execPath, entry };
}

function quoteWindows(value: string): string {
  return `"${value.replace(/"/g, '\\"')}"`;
}

function quoteShell(value: string): string {
  return `'${value.replace(/'/g, "'\\''")}'`;
}

function xml(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function macPath(): string {
  return join(homedir(), 'Library', 'LaunchAgents', launchAgentName);
}

function linuxPath(): string {
  return join(process.env.XDG_CONFIG_HOME ?? join(homedir(), '.config'), 'systemd', 'user', systemdServiceName);
}

export async function installAgentAutoStart(): Promise<AutoStartStatus> {
  const target = platform();
  const command = launchCommand();
  if (target === 'win32') {
    await execFile('schtasks.exe', [
      '/Create', '/TN', taskName, '/SC', 'ONLOGON', '/RL', 'LIMITED',
      '/TR', `${quoteWindows(command.node)} ${quoteWindows(command.entry)} agent serve`, '/F',
    ]);
    return { platform: 'windows', installed: true, location: `Task Scheduler: ${taskName}` };
  }
  if (target === 'darwin') {
    const location = macPath();
    await mkdir(dirname(location), { recursive: true });
    const source = `<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>\n  <key>Label</key><string>com.dayhawk.float.agent</string>\n  <key>ProgramArguments</key><array><string>${xml(command.node)}</string><string>${xml(command.entry)}</string><string>agent</string><string>serve</string></array>\n  <key>RunAtLoad</key><true/>\n  <key>KeepAlive</key><true/>\n  <key>ProcessType</key><string>Background</string>\n</dict></plist>\n`;
    await writeFile(location, source, 'utf8');
    const domain = `gui/${userInfo().uid}`;
    await execFile('launchctl', ['bootout', domain, location]).catch(() => undefined);
    await execFile('launchctl', ['bootstrap', domain, location]);
    return { platform: 'macos', installed: true, location };
  }
  if (target === 'linux') {
    const location = linuxPath();
    await mkdir(dirname(location), { recursive: true });
    const source = `[Unit]\nDescription=Float paired-device agent\nAfter=network-online.target\n\n[Service]\nType=simple\nExecStart=${quoteShell(command.node)} ${quoteShell(command.entry)} agent serve\nRestart=on-failure\nRestartSec=3\n\n[Install]\nWantedBy=default.target\n`;
    await writeFile(location, source, 'utf8');
    await execFile('systemctl', ['--user', 'daemon-reload']);
    await execFile('systemctl', ['--user', 'enable', '--now', systemdServiceName]);
    return { platform: 'linux', installed: true, location };
  }
  throw new Error(`Automatic startup is not supported on ${target}.`);
}

export async function agentAutoStartStatus(): Promise<AutoStartStatus> {
  const target = platform();
  if (target === 'win32') {
    const installed = await execFile('schtasks.exe', ['/Query', '/TN', taskName]).then(() => true).catch(() => false);
    return { platform: 'windows', installed, location: `Task Scheduler: ${taskName}` };
  }
  if (target === 'darwin') {
    const location = macPath();
    const installed = await access(location).then(() => true).catch(() => false);
    return { platform: 'macos', installed, location };
  }
  if (target === 'linux') {
    const location = linuxPath();
    const installed = await execFile('systemctl', ['--user', 'is-enabled', systemdServiceName]).then(() => true).catch(() => false);
    return { platform: 'linux', installed, location };
  }
  throw new Error(`Automatic startup is not supported on ${target}.`);
}

export async function uninstallAgentAutoStart(): Promise<AutoStartStatus> {
  const target = platform();
  if (target === 'win32') {
    await execFile('schtasks.exe', ['/Delete', '/TN', taskName, '/F']).catch(() => undefined);
    return { platform: 'windows', installed: false, location: `Task Scheduler: ${taskName}` };
  }
  if (target === 'darwin') {
    const location = macPath();
    await execFile('launchctl', ['bootout', `gui/${userInfo().uid}`, location]).catch(() => undefined);
    await rm(location, { force: true });
    return { platform: 'macos', installed: false, location };
  }
  if (target === 'linux') {
    const location = linuxPath();
    await execFile('systemctl', ['--user', 'disable', '--now', systemdServiceName]).catch(() => undefined);
    await rm(location, { force: true });
    await execFile('systemctl', ['--user', 'daemon-reload']).catch(() => undefined);
    return { platform: 'linux', installed: false, location };
  }
  throw new Error(`Automatic startup is not supported on ${target}.`);
}
