import { randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { z } from 'zod';

const snippetSchema = z.object({
  id: z.string().uuid(),
  title: z.string().min(1),
  body: z.string(),
  tags: z.array(z.string()),
  list: z.string().nullable(),
  pinned: z.boolean(),
  createdAt: z.string(),
  updatedAt: z.string(),
  lastUsedAt: z.string().nullable(),
});

const databaseSchema = z.object({
  version: z.literal(1),
  snippets: z.array(snippetSchema),
});

export type Snippet = z.infer<typeof snippetSchema>;
export type SnippetStore = Pick<FloatStore, 'list' | 'get' | 'create' | 'update' | 'markUsed' | 'remove' | 'export'>;
type Database = z.infer<typeof databaseSchema>;

export class FloatStore {
  constructor(private readonly filePath = join(process.env.FLOAT_HOME ?? join(homedir(), '.float'), 'snippets.json')) {}

  private async read(): Promise<Database> {
    try {
      return databaseSchema.parse(JSON.parse(await readFile(this.filePath, 'utf8')));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        return { version: 1, snippets: [] };
      }
      throw new Error(`Could not read Float data at ${this.filePath}: ${(error as Error).message}`);
    }
  }

  private async save(data: Database): Promise<void> {
    await mkdir(dirname(this.filePath), { recursive: true });
    const temporaryPath = `${this.filePath}.tmp`;
    await writeFile(temporaryPath, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
    await rename(temporaryPath, this.filePath);
  }

  async list(query?: string): Promise<Snippet[]> {
    const { snippets } = await this.read();
    const normalizedQuery = query?.trim().toLocaleLowerCase();
    return snippets
      .filter((snippet) => !normalizedQuery || [snippet.title, snippet.body, snippet.list ?? '', ...snippet.tags].join('\n').toLocaleLowerCase().includes(normalizedQuery))
      .sort((left, right) => Number(right.pinned) - Number(left.pinned) || right.updatedAt.localeCompare(left.updatedAt));
  }

  async get(id: string): Promise<Snippet> {
    const snippet = (await this.read()).snippets.find((item) => item.id === id);
    if (!snippet) throw new Error(`No Float snippet found with id ${id}.`);
    return snippet;
  }

  async create(input: Pick<Snippet, 'title' | 'body'> & Partial<Pick<Snippet, 'tags' | 'list' | 'pinned'>>): Promise<Snippet> {
    const timestamp = new Date().toISOString();
    const snippet = snippetSchema.parse({
      id: randomUUID(), title: input.title.trim(), body: input.body,
      tags: input.tags?.map((tag) => tag.trim()).filter(Boolean) ?? [],
      list: input.list?.trim() || null, pinned: input.pinned ?? false,
      createdAt: timestamp, updatedAt: timestamp, lastUsedAt: null,
    });
    const database = await this.read();
    database.snippets.push(snippet);
    await this.save(database);
    return snippet;
  }

  async update(id: string, input: Partial<Pick<Snippet, 'title' | 'body' | 'tags' | 'list' | 'pinned'>>): Promise<Snippet> {
    const database = await this.read();
    const index = database.snippets.findIndex((item) => item.id === id);
    if (index === -1) throw new Error(`No Float snippet found with id ${id}.`);
    const existing = database.snippets[index];
    const updated = snippetSchema.parse({ ...existing, ...input, updatedAt: new Date().toISOString() });
    database.snippets[index] = updated;
    await this.save(database);
    return updated;
  }

  async markUsed(id: string): Promise<Snippet> {
    const database = await this.read();
    const index = database.snippets.findIndex((item) => item.id === id);
    if (index === -1) throw new Error(`No Float snippet found with id ${id}.`);
    const updated = { ...database.snippets[index], lastUsedAt: new Date().toISOString(), updatedAt: database.snippets[index].updatedAt };
    database.snippets[index] = updated;
    await this.save(database);
    return updated;
  }

  async remove(id: string): Promise<void> {
    const database = await this.read();
    const snippets = database.snippets.filter((item) => item.id !== id);
    if (snippets.length === database.snippets.length) throw new Error(`No Float snippet found with id ${id}.`);
    await this.save({ ...database, snippets });
  }

  async export(): Promise<Database> { return this.read(); }
}
