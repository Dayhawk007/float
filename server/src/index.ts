import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { AccountStore, type SnippetInput } from './store.js';

const port = Number(process.env.PORT ?? 8787);
const host = process.env.FLOAT_BIND_HOST ?? '127.0.0.1';
const store = new AccountStore();

function send(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  response.end(JSON.stringify(body));
}

async function body(request: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(Buffer.from(chunk));
    if (Buffer.concat(chunks).length > 1_000_000) throw new Error('Request body is too large.');
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8')) as Record<string, unknown>;
}

function string(value: unknown, field: string, minLength = 1): string {
  if (typeof value !== 'string' || value.trim().length < minLength) throw new Error(`${field} is required.`);
  return value;
}

async function authenticated(request: IncomingMessage) {
  const value = request.headers.authorization;
  if (!value?.startsWith('Bearer ')) throw new Error('Authentication is required.');
  return store.userForToken(value.slice('Bearer '.length));
}

const server = createServer(async (request, response) => {
  try {
    const method = request.method ?? 'GET';
    const path = new URL(request.url ?? '/', `http://${request.headers.host ?? 'localhost'}`).pathname;
    if (method === 'GET' && path === '/health') return send(response, 200, { ok: true });
    if (method === 'POST' && (path === '/v1/auth/register' || path === '/v1/auth/login')) {
      const input = await body(request);
      const email = string(input.email, 'email');
      const password = string(input.password, 'password', 8);
      const session = path.endsWith('register') ? await store.register(email, password) : await store.login(email, password);
      return send(response, 200, session);
    }
    const user = await authenticated(request);
    if (method === 'GET' && path === '/v1/me') return send(response, 200, { user });
    if (method === 'GET' && path === '/v1/snippets') return send(response, 200, { snippets: await store.listSnippets(user.id) });
    const match = path.match(/^\/v1\/snippets\/([^/]+)$/);
    if (match && method === 'PUT') {
      const input = await body(request);
      const id = decodeURIComponent(match[1]);
      const snippet: SnippetInput = {
        id,
        title: string(input.title, 'title'),
        body: typeof input.body === 'string' ? input.body : '',
        pinned: input.pinned === true,
        updatedAt: string(input.updatedAt, 'updatedAt'),
        createdAt: typeof input.createdAt === 'string' ? input.createdAt : undefined,
        tags: Array.isArray(input.tags) ? input.tags.filter((tag): tag is string => typeof tag === 'string') : undefined,
        list: typeof input.list === 'string' || input.list === null ? input.list : undefined,
        lastUsedAt: typeof input.lastUsedAt === 'string' || input.lastUsedAt === null ? input.lastUsedAt : undefined,
      };
      return send(response, 200, { snippet: await store.upsertSnippet(user.id, snippet) });
    }
    if (match && method === 'DELETE') {
      await store.deleteSnippet(user.id, decodeURIComponent(match[1]));
      return send(response, 204, null);
    }
    return send(response, 404, { error: 'Not found.' });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected server error.';
    const status = /authentication|session|invalid email/i.test(message) ? 401 : 400;
    return send(response, status, { error: message });
  }
});

server.listen(port, host, () => console.log(`Float local account API listening at http://${host}:${port}`));
