#!/usr/bin/env node
import { writeFile } from 'node:fs/promises';
import { Command } from 'commander';
import clipboard from 'clipboardy';
import type { Snippet } from './store.js';
import { startMcpServer } from './mcp.js';
import { activeStore, authenticate, clearSession, loadSession } from './account.js';

const store = await activeStore();
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
const auth = program.command('auth').description('Configure the account-backed Float API for CLI and MCP use.');
auth.command('register').requiredOption('--api <url>').requiredOption('--email <email>').requiredOption('--password <password>').action(async (options) => {
  const session = await authenticate(options.api, options.email, options.password, 'register');
  console.log(`Signed in as ${session.email}.`);
});
auth.command('login').requiredOption('--api <url>').requiredOption('--email <email>').requiredOption('--password <password>').action(async (options) => {
  const session = await authenticate(options.api, options.email, options.password, 'login');
  console.log(`Signed in as ${session.email}.`);
});
auth.command('status').action(async () => {
  const session = await loadSession();
  console.log(session ? `Signed in as ${session.email} (${session.apiUrl})` : 'Using the local-only store.');
});
auth.command('logout').action(async () => { await clearSession(); console.log('Signed out.'); });
program.command('sync').description('Confirm that this CLI and its MCP server use the account-backed store.').action(async () => {
  const session = await loadSession();
  if (!session) throw new Error('Sign in with `float auth login` before syncing.');
  console.log(`Account sync is active for ${session.email}.`);
});
program.command('mcp').description('Run Float as a local stdio MCP server').command('serve').description('Start the local-only MCP server').action(async () => startMcpServer(await activeStore()));

program.parseAsync().catch((error: Error) => { console.error(`float: ${error.message}`); process.exitCode = 1; });
