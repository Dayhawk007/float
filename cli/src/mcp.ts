import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { FloatStore } from './store.js';

function result(value: unknown) {
  return { content: [{ type: 'text' as const, text: JSON.stringify(value, null, 2) }] };
}

export async function startMcpServer(): Promise<void> {
  const store = new FloatStore();
  const server = new McpServer({ name: 'float', version: '0.1.0' });

  server.registerTool('search_snippets', {
    title: 'Search Float snippets',
    description: 'Search the locally stored Float notes and reusable clipboard snippets.',
    inputSchema: { query: z.string().default('') },
  }, async ({ query }) => result(await store.list(query)));

  server.registerTool('get_snippet', {
    title: 'Get a Float snippet',
    description: 'Read one locally stored Float snippet by ID.',
    inputSchema: { id: z.string().uuid() },
  }, async ({ id }) => result(await store.get(id)));

  server.registerTool('create_snippet', {
    title: 'Create a Float snippet',
    description: 'Save a new local Float snippet. This writes only to the current user’s local Float store.',
    inputSchema: { title: z.string().min(1), body: z.string(), tags: z.array(z.string()).optional(), list: z.string().optional(), pinned: z.boolean().optional() },
  }, async (input) => result(await store.create(input)));

  server.registerTool('update_snippet', {
    title: 'Update a Float snippet',
    description: 'Update title, body, tags, list, or pinned status of a local Float snippet.',
    inputSchema: { id: z.string().uuid(), title: z.string().min(1).optional(), body: z.string().optional(), tags: z.array(z.string()).optional(), list: z.string().nullable().optional(), pinned: z.boolean().optional() },
  }, async ({ id, ...fields }) => result(await store.update(id, fields)));

  await server.connect(new StdioServerTransport());
}
