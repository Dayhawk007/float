import { randomBytes, randomUUID, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCallback);
const sessionLifetimeMs = 1000 * 60 * 60 * 24 * 30;

export type SnippetInput = {
  id: string;
  title: string;
  body: string;
  pinned: boolean;
  updatedAt: string;
  createdAt?: string;
  tags?: string[];
  list?: string | null;
  lastUsedAt?: string | null;
};

export type RemoteSnippet = Required<Omit<SnippetInput, 'createdAt' | 'tags' | 'list' | 'lastUsedAt'>> & {
  createdAt: string;
  tags: string[];
  list: string | null;
  lastUsedAt: string | null;
};

type User = { id: string; email: string; passwordHash: string; passwordSalt: string; createdAt: string };
type Session = { id: string; userId: string; tokenHash: string; expiresAt: string; createdAt: string };
type Database = { version: 1; users: User[]; sessions: Session[]; snippets: Array<RemoteSnippet & { userId: string }> };

export class AccountStore {
  constructor(private readonly filePath = process.env.FLOAT_SERVER_DATA ?? join(homedir(), '.float-server', 'database.json')) {}

  private async read(): Promise<Database> {
    try {
      return JSON.parse(await readFile(this.filePath, 'utf8')) as Database;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') return { version: 1, users: [], sessions: [], snippets: [] };
      throw error;
    }
  }

  private async save(database: Database): Promise<void> {
    await mkdir(dirname(this.filePath), { recursive: true });
    const temporaryPath = `${this.filePath}.tmp`;
    await writeFile(temporaryPath, `${JSON.stringify(database, null, 2)}\n`, 'utf8');
    await rename(temporaryPath, this.filePath);
  }

  private async passwordHash(password: string, salt: string): Promise<string> {
    return (await scrypt(password, salt, 64) as Buffer).toString('hex');
  }

  private async createSession(database: Database, userId: string): Promise<{ accessToken: string; expiresAt: string }> {
    const secret = randomBytes(32).toString('base64url');
    const sessionId = randomUUID();
    const expiresAt = new Date(Date.now() + sessionLifetimeMs).toISOString();
    database.sessions = database.sessions.filter((session) => new Date(session.expiresAt).getTime() > Date.now());
    database.sessions.push({
      id: sessionId,
      userId,
      tokenHash: (await scrypt(secret, sessionId, 64) as Buffer).toString('hex'),
      expiresAt,
      createdAt: new Date().toISOString(),
    });
    await this.save(database);
    return { accessToken: `${sessionId}.${secret}`, expiresAt };
  }

  async register(email: string, password: string): Promise<{ user: Pick<User, 'id' | 'email'>; accessToken: string; expiresAt: string }> {
    const normalizedEmail = email.trim().toLowerCase();
    const database = await this.read();
    if (database.users.some((user) => user.email === normalizedEmail)) throw new Error('An account already exists for this email.');
    const passwordSalt = randomBytes(16).toString('hex');
    const user: User = {
      id: randomUUID(),
      email: normalizedEmail,
      passwordSalt,
      passwordHash: await this.passwordHash(password, passwordSalt),
      createdAt: new Date().toISOString(),
    };
    database.users.push(user);
    const session = await this.createSession(database, user.id);
    return { user: { id: user.id, email: user.email }, ...session };
  }

  async login(email: string, password: string): Promise<{ user: Pick<User, 'id' | 'email'>; accessToken: string; expiresAt: string }> {
    const database = await this.read();
    const user = database.users.find((item) => item.email === email.trim().toLowerCase());
    if (!user) throw new Error('Invalid email or password.');
    const candidate = await this.passwordHash(password, user.passwordSalt);
    if (!timingSafeEqual(Buffer.from(candidate, 'hex'), Buffer.from(user.passwordHash, 'hex'))) throw new Error('Invalid email or password.');
    const session = await this.createSession(database, user.id);
    return { user: { id: user.id, email: user.email }, ...session };
  }

  async userForToken(token: string): Promise<Pick<User, 'id' | 'email'>> {
    const [sessionId, secret] = token.split('.', 2);
    if (!sessionId || !secret) throw new Error('Invalid access token.');
    const database = await this.read();
    const session = database.sessions.find((item) => item.id === sessionId && new Date(item.expiresAt).getTime() > Date.now());
    if (!session) throw new Error('Session expired or invalid.');
    const candidate = (await scrypt(secret, sessionId, 64) as Buffer).toString('hex');
    if (!timingSafeEqual(Buffer.from(candidate, 'hex'), Buffer.from(session.tokenHash, 'hex'))) throw new Error('Session expired or invalid.');
    const user = database.users.find((item) => item.id === session.userId);
    if (!user) throw new Error('Account no longer exists.');
    return { id: user.id, email: user.email };
  }

  async listSnippets(userId: string): Promise<RemoteSnippet[]> {
    const database = await this.read();
    return database.snippets.filter((snippet) => snippet.userId === userId).map(({ userId: _userId, ...snippet }) => snippet)
      .sort((left, right) => Number(right.pinned) - Number(left.pinned) || right.updatedAt.localeCompare(left.updatedAt));
  }

  async upsertSnippet(userId: string, input: SnippetInput): Promise<RemoteSnippet> {
    const database = await this.read();
    const index = database.snippets.findIndex((snippet) => snippet.userId === userId && snippet.id === input.id);
    const existing = index === -1 ? undefined : database.snippets[index];
    const snippet: RemoteSnippet & { userId: string } = {
      userId,
      id: input.id,
      title: input.title.trim(),
      body: input.body,
      pinned: input.pinned,
      updatedAt: input.updatedAt,
      createdAt: input.createdAt ?? existing?.createdAt ?? new Date().toISOString(),
      tags: input.tags ?? existing?.tags ?? [],
      list: input.list ?? existing?.list ?? null,
      lastUsedAt: input.lastUsedAt ?? existing?.lastUsedAt ?? null,
    };
    if (index === -1) database.snippets.push(snippet); else database.snippets[index] = snippet;
    await this.save(database);
    const { userId: _userId, ...result } = snippet;
    return result;
  }

  async deleteSnippet(userId: string, id: string): Promise<void> {
    const database = await this.read();
    database.snippets = database.snippets.filter((snippet) => !(snippet.userId === userId && snippet.id === id));
    await this.save(database);
  }
}
