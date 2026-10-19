#!/usr/bin/env node
import { writeFile } from 'node:fs/promises';
import { Command } from 'commander';
import clipboard from 'clipboardy';
import { FloatStore, type Snippet } from './store.js';
import { startMcpServer } from './mcp.js';
import { startPairingAgent } from './pairing_agent.js';
import { agentAutoStartStatus, installAgentAutoStart, uninstallAgentAutoStart } from './agent_autostart.js';

const store = new FloatStore();
const program = new Command();

function print(value: unknown, json?: boolean): void {
  if (json) console.log(JSON.stringify(value, null, 2));
  else if (Array.isArray(value)) value.forEach((snippet) => console.log(formatSnippet(snippet as Snippet)));
  else console.log(formatSnippet(value as Snippet));
}

function formatSnippet(snippet: Snippet): string {
  return `${snippet.id}\n${snippet.pinned ? '★ ' : ''}${snippet.title}  ·  ${snippet.group}\n${snippet.body}`;
}

program.name('float').description('Local-first notes and clipboard companion').version('0.1.0').showSuggestionAfterError();

program.command('list').description('List saved snippets').option('-q, --query <query>').option('--group <group>', 'Only notes in this group').option('--json').action(async (options) => print(await store.list(options.query, options.group), options.json));
program.command('search <query>').description('Search saved snippets').option('--group <group>', 'Only notes in this group').option('--json').action(async (query, options) => print(await store.list(query, options.group), options.json));
program.command('get <id>').description('Read one snippet').option('--json').action(async (id, options) => print(await store.get(id), options.json));
program.command('create').description('Create a snippet').requiredOption('-t, --title <title>').requiredOption('-b, --body <body>').option('--list <list>').option('--group <group>', 'Note group', 'General').option('--pin').option('--json').action(async (options) => print(await store.create({ title: options.title, body: options.body, list: options.list, group: options.group, pinned: options.pin }), options.json));
program.command('update <id>').description('Update a snippet').option('-t, --title <title>').option('-b, --body <body>').option('--list <list>').option('--group <group>', 'Note group').option('--pin').option('--unpin').option('--json').action(async (id, options) => {
  if (![options.title, options.body, options.list, options.group, options.pin, options.unpin].some((value) => value !== undefined)) throw new Error('Provide at least one field to update.');
  print(await store.update(id, { title: options.title, body: options.body, list: options.list, group: options.group, pinned: options.pin ? true : options.unpin ? false : undefined }), options.json);
});
program.command('copy <id>').description('Copy a snippet body to the system clipboard').option('--json').action(async (id, options) => { const snippet = await store.get(id); await clipboard.write(snippet.body); print(snippet, options.json); });
program.command('delete <id>').description('Permanently delete a snippet').requiredOption('--yes', 'Confirm permanent deletion').action(async (id) => { await store.remove(id); console.log(`Deleted ${id}`); });
program.command('export <path>').description('Export all local Float data as JSON').action(async (path) => { await writeFile(path, `${JSON.stringify(await store.export(), null, 2)}\n`, 'utf8'); console.log(`Exported Float data to ${path}`); });
program.command('mcp').description('Run Float as a local stdio MCP server').command('serve').description('Start the local-only MCP server').action(startMcpServer);
program.command('pair').description('Pair an Android device with this local Float store').command('serve').description('Show a QR code and serve paired devices on the local network').option('--host <host>', 'Address to bind', '0.0.0.0').option('--port <port>', 'Port to listen on', '8787').option('--url <url>', 'LAN URL to place in the pairing QR code').option('--duration <seconds>', 'Stop after this many seconds').action((options) => startPairingAgent({ host: options.host, port: Number(options.port), advertiseUrl: options.url, durationSeconds: options.duration ? Number(options.duration) : undefined }));
const agent = program.command('agent').description('Manage the persistent paired-device agent');
agent.command('serve').description('Serve already-paired devices and advertise on the trusted LAN').option('--host <host>', 'Address to bind', '0.0.0.0').option('--port <port>', 'Port to listen on', '8787').option('--url <url>', 'LAN URL to advertise').action((options) => startPairingAgent({ host: options.host, port: Number(options.port), advertiseUrl: options.url, pairing: false }));
agent.command('install').description('Start the persistent local agent automatically when you sign in').action(async () => { const status = await installAgentAutoStart(); console.log(`Installed Float agent auto-start (${status.platform}) at ${status.location}`); });
agent.command('status').description('Show whether the persistent local agent starts automatically').action(async () => { const status = await agentAutoStartStatus(); console.log(JSON.stringify(status, null, 2)); });
agent.command('uninstall').description('Stop and remove the persistent agent auto-start entry').action(async () => { const status = await uninstallAgentAutoStart(); console.log(`Removed Float agent auto-start (${status.platform}) from ${status.location}`); });

program.parseAsync().catch((error: Error) => { console.error(`float: ${error.message}`); process.exitCode = 1; });
