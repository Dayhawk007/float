#!/usr/bin/env node
import { writeFile } from 'node:fs/promises';
import { Command } from 'commander';
import clipboard from 'clipboardy';
import { FloatStore, type Snippet } from './store.js';
import { startMcpServer } from './mcp.js';
import { startPairingAgent } from './pairing_agent.js';

const store = new FloatStore();
const program = new Command();

function print(value: unknown, json?: boolean): void {
  if (json) console.log(JSON.stringify(value, null, 2));
  else if (Array.isArray(value)) value.forEach((snippet) => console.log(formatSnippet(snippet as Snippet)));
  else console.log(formatSnippet(value as Snippet));
}

function formatSnippet(snippet: Snippet): string {
  return `${snippet.id}\n${snippet.pinned ? '★ ' : ''}${snippet.title}${snippet.tags.length ? `  #${snippet.tags.join(' #')}` : ''}\n${snippet.body}`;
}

function splitTags(value?: string): string[] | undefined { return value?.split(',').map((tag) => tag.trim()).filter(Boolean); }

program.name('float').description('Local-first notes and clipboard companion').version('0.1.0').showSuggestionAfterError();

program.command('list').description('List saved snippets').option('-q, --query <query>').option('--json').action(async (options) => print(await store.list(options.query), options.json));
program.command('search <query>').description('Search saved snippets').option('--json').action(async (query, options) => print(await store.list(query), options.json));
program.command('get <id>').description('Read one snippet').option('--json').action(async (id, options) => print(await store.get(id), options.json));
program.command('create').description('Create a snippet').requiredOption('-t, --title <title>').requiredOption('-b, --body <body>').option('--tags <tags>', 'Comma-separated tags').option('--list <list>').option('--pin').option('--json').action(async (options) => print(await store.create({ title: options.title, body: options.body, tags: splitTags(options.tags), list: options.list, pinned: options.pin }), options.json));
program.command('update <id>').description('Update a snippet').option('-t, --title <title>').option('-b, --body <body>').option('--tags <tags>').option('--list <list>').option('--pin').option('--unpin').option('--json').action(async (id, options) => {
  if (![options.title, options.body, options.tags, options.list, options.pin, options.unpin].some((value) => value !== undefined)) throw new Error('Provide at least one field to update.');
  print(await store.update(id, { title: options.title, body: options.body, tags: splitTags(options.tags), list: options.list, pinned: options.pin ? true : options.unpin ? false : undefined }), options.json);
});
program.command('copy <id>').description('Copy a snippet body to the system clipboard').option('--json').action(async (id, options) => { const snippet = await store.get(id); await clipboard.write(snippet.body); print(snippet, options.json); });
program.command('delete <id>').description('Permanently delete a snippet').requiredOption('--yes', 'Confirm permanent deletion').action(async (id) => { await store.remove(id); console.log(`Deleted ${id}`); });
program.command('export <path>').description('Export all local Float data as JSON').action(async (path) => { await writeFile(path, `${JSON.stringify(await store.export(), null, 2)}\n`, 'utf8'); console.log(`Exported Float data to ${path}`); });
program.command('mcp').description('Run Float as a local stdio MCP server').command('serve').description('Start the local-only MCP server').action(startMcpServer);
program.command('pair').description('Pair an Android device with this local Float store').command('serve').description('Show a QR code and serve paired devices on the local network').option('--host <host>', 'Address to bind', '0.0.0.0').option('--port <port>', 'Port to listen on', '8787').option('--url <url>', 'LAN URL to place in the pairing QR code').option('--duration <seconds>', 'Stop after this many seconds').action((options) => startPairingAgent({ host: options.host, port: Number(options.port), advertiseUrl: options.url, durationSeconds: options.duration ? Number(options.duration) : undefined }));

program.parseAsync().catch((error: Error) => { console.error(`float: ${error.message}`); process.exitCode = 1; });
