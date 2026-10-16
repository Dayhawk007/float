import { randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, unlink, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { FloatStore, type Snippet, type SnippetStore } from './store.js';

export type AccountSession = { apiUrl: string; accessToken: string; email: string; expiresAt: string };
const sessionPath = join(process.env.FLOAT_HOME ?? join(homedir(), '.float'), 'account-session.json');

async function request<T>(session: Pick<AccountSession, 'apiUrl' | 'accessToken'>, path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${session.apiUrl.replace(/\/$/, '')}${path}`, {
    ...init,
    headers: { authorization: `Bearer ${session.accessToken}`, 'content-type': 'application/json', ...init?.headers },
  });
  const payload = await response.json() as T & { error?: string };
  if (!response.ok) throw new Error(payload.error ?? `Account API returned ${response.status}.`);
  return payload;
}

export async function loadSession(): Promise<AccountSession | undefined> {
  try { return JSON.parse(await readFile(sessionPath, 'utf8')) as AccountSession; } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return undefined;
    throw error;
  }
}

export async function saveSession(session: AccountSession): Promise<void> {
  await mkdir(dirname(sessionPath), { recursive: true });
  const temporaryPath = `${sessionPath}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(session, null, 2)}\n`, 'utf8');
  await rename(temporaryPath, sessionPath);
}

export async function clearSession(): Promise<void> {
  try { await unlink(sessionPath); } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
  }
}

export async function authenticate(apiUrl: string, email: string, password: string, action: 'register' | 'login'): Promise<AccountSession> {
  const response = await fetch(`${apiUrl.replace(/\/$/, '')}/v1/auth/${action}`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, password }),
  });
  const payload = await response.json() as { user?: { email: string }; accessToken?: string; expiresAt?: string; error?: string };
  if (!response.ok || !payload.user || !payload.accessToken || !payload.expiresAt) throw new Error(payload.error ?? 'Could not authenticate.');
  const session = { apiUrl: apiUrl.replace(/\/$/, ''), email: payload.user.email, accessToken: payload.accessToken, expiresAt: payload.expiresAt };
  await saveSession(session);
  return session;
}

export class RemoteStore implements SnippetStore {
  constructor(private readonly session: AccountSession) {}

  async list(query?: string): Promise<Snippet[]> {
    const { snippets } = await request<{ snippets: Snippet[] }>(this.session, '/v1/snippets');
    const normalized = query?.trim().toLowerCase();
    return snippets.filter((snippet) => !normalized || [snippet.title, snippet.body, snippet.list ?? '', ...snippet.tags].join('\n').toLowerCase().includes(normalized));
  }

  async get(id: string): Promise<Snippet> {
    const snippet = (await this.list()).find((item) => item.id === id);
    if (!snippet) throw new Error(`No Float snippet found with id ${id}.`);
    return snippet;
  }

  async create(input: Pick<Snippet, 'title' | 'body'> & Partial<Pick<Snippet, 'tags' | 'list' | 'pinned'>>): Promise<Snippet> {
    const timestamp = new Date().toISOString();
    return this.put({ id: randomUUID(), title: input.title.trim(), body: input.body, tags: input.tags ?? [], list: input.list ?? null, pinned: input.pinned ?? false, createdAt: timestamp, updatedAt: timestamp, lastUsedAt: null });
  }

  async update(id: string, input: Partial<Pick<Snippet, 'title' | 'body' | 'tags' | 'list' | 'pinned'>>): Promise<Snippet> {
    return this.put({ ...await this.get(id), ...input, updatedAt: new Date().toISOString() });
  }

  async markUsed(id: string): Promise<Snippet> { return this.get(id); }

  async remove(id: string): Promise<void> {
    const response = await fetch(`${this.session.apiUrl}/v1/snippets/${encodeURIComponent(id)}`, { method: 'DELETE', headers: { authorization: `Bearer ${this.session.accessToken}` } });
    if (!response.ok) throw new Error(`Could not delete snippet (${response.status}).`);
  }

  async export(): Promise<{ version: 1; snippets: Snippet[] }> { return { version: 1, snippets: await this.list() }; }

  private async put(snippet: Snippet): Promise<Snippet> {
    const payload = await request<{ snippet: Snippet }>(this.session, `/v1/snippets/${encodeURIComponent(snippet.id)}`, { method: 'PUT', body: JSON.stringify(snippet) });
    return payload.snippet;
  }
}

export async function activeStore(): Promise<SnippetStore> {
  const session = await loadSession();
  return session ? new RemoteStore(session) : new FloatStore();
}
