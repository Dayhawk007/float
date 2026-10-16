import { createHash, randomBytes, randomInt, randomUUID, timingSafeEqual } from 'node:crypto';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { homedir, networkInterfaces } from 'node:os';
import { dirname, join } from 'node:path';
import qrcode from 'qrcode-terminal';
import { z } from 'zod';
import { FloatStore, type Snippet } from './store.js';

const pairingSchema = z.object({ deviceId: z.string().min(1).max(128), deviceName: z.string().min(1).max(128) });
const snippetSchema = z.object({
  id: z.string().min(1), title: z.string().min(1), body: z.string(),
  tags: z.array(z.string()).default([]), list: z.string().nullable().default(null),
  pinned: z.boolean().default(false), createdAt: z.string(), updatedAt: z.string(), lastUsedAt: z.string().nullable().default(null),
});

type PairedDevice = { id: string; name: string; tokenHash: string; pairedAt: string };
type PairingDatabase = { version: 1; devices: PairedDevice[] };

function floatHome(): string { return process.env.FLOAT_HOME ?? join(homedir(), '.float'); }
function hash(value: string): string { return createHash('sha256').update(value).digest('hex'); }
function token(): string { return randomBytes(32).toString('base64url'); }
function log(event: string, details: Record<string, unknown> = {}): void {
  console.log(`[float-agent] ${JSON.stringify({ timestamp: new Date().toISOString(), event, ...details })}`);
}
function json(response: ServerResponse, status: number, value: unknown): void {
  response.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  response.end(JSON.stringify(value));
}
async function body(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const item = Buffer.from(chunk);
    size += item.length;
    if (size > 1_000_000) throw new Error('Request body is too large.');
    chunks.push(item);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}
function lanAddress(): string | undefined {
  const candidates = Object.entries(networkInterfaces())
    .flatMap(([name, addresses]) => (addresses ?? []).map((address) => ({ name, address })))
    .filter(({ address }) => address.family === 'IPv4' && !address.internal && !address.address.startsWith('169.254.'))
    .sort((left, right) => interfaceScore(right.name) - interfaceScore(left.name));
  log('network.addresses.detected', {
    candidates: candidates.map(({ name, address }) => ({ name, address: address.address })),
  });
  return candidates[0]?.address.address;
}

function interfaceScore(name: string): number {
  if (/(wsl|hyper-v|virtual|vmware|docker|loopback)/i.test(name)) return -100;
  if (/(wi-?fi|wlan|wireless)/i.test(name)) return 100;
  if (/ethernet/i.test(name)) return 50;
  return 0;
}

class DeviceRegistry {
  private readonly filePath = join(floatHome(), 'paired-devices.json');
  async read(): Promise<PairingDatabase> {
    try { return JSON.parse(await readFile(this.filePath, 'utf8')) as PairingDatabase; }
    catch (error) { if ((error as NodeJS.ErrnoException).code === 'ENOENT') return { version: 1, devices: [] }; throw error; }
  }
  async save(database: PairingDatabase): Promise<void> {
    await mkdir(dirname(this.filePath), { recursive: true });
    const temporary = `${this.filePath}.tmp`;
    await writeFile(temporary, `${JSON.stringify(database, null, 2)}\n`, 'utf8');
    await rename(temporary, this.filePath);
  }
  async issue(device: { deviceId: string; deviceName: string }): Promise<string> {
    const database = await this.read();
    const deviceToken = token();
    database.devices = database.devices.filter((item) => item.id !== device.deviceId);
    database.devices.push({ id: device.deviceId, name: device.deviceName, tokenHash: hash(deviceToken), pairedAt: new Date().toISOString() });
    await this.save(database);
    return deviceToken;
  }
  async valid(deviceToken: string | undefined): Promise<boolean> {
    if (!deviceToken) return false;
    const candidate = Buffer.from(hash(deviceToken), 'utf8');
    return (await this.read()).devices.some((device) => {
      const stored = Buffer.from(device.tokenHash, 'utf8');
      return stored.length === candidate.length && timingSafeEqual(stored, candidate);
    });
  }
}

function bearer(request: IncomingMessage): string | undefined {
  const value = request.headers.authorization;
  return value?.startsWith('Bearer ') ? value.slice('Bearer '.length) : undefined;
}

export async function startPairingAgent(options: { host?: string; port?: number; advertiseUrl?: string; durationSeconds?: number } = {}): Promise<void> {
  const host = options.host ?? '0.0.0.0';
  const port = options.port ?? 8787;
  const advertisedHost = options.advertiseUrl ?? lanAddress();
  if (!advertisedHost) throw new Error('No LAN IPv4 address found. Connect to Wi-Fi or pass --url http://HOST:PORT.');
  const agentUrl = options.advertiseUrl ?? `http://${advertisedHost}:${port}`;
  const oneTimeToken = token();
  const manualCode = String(randomInt(10_000_000, 100_000_000));
  const expiresAt = Date.now() + 10 * 60 * 1000;
  let manualCodeAttempts = 0;
  const registry = new DeviceRegistry();
  const restoredDeviceCount = (await registry.read()).devices.length;
  const store = new FloatStore();
  const server = createServer(async (request, response) => {
    const requestId = randomUUID().slice(0, 8);
    try {
      const pathname = new URL(request.url ?? '/', agentUrl).pathname;
      log('request.received', { requestId, method: request.method, pathname, remoteAddress: request.socket.remoteAddress });
      if (request.method === 'GET' && pathname === '/v1/health') {
        log('health.succeeded', { requestId });
        return json(response, 200, { status: 'ok', protocol: 1 });
      }
      if (request.method === 'POST' && pathname === '/v1/pair') {
        const payload = pairingSchema.parse(await body(request));
        const supplied = request.headers['x-float-pairing-token'];
        const suppliedCode = request.headers['x-float-pairing-code'];
        const expected = Buffer.from(oneTimeToken, 'utf8');
        const provided = Buffer.from(typeof supplied === 'string' ? supplied : '', 'utf8');
        const code = typeof suppliedCode === 'string' ? suppliedCode : '';
        const tokenMatches = provided.length === expected.length && timingSafeEqual(provided, expected);
        const codeMatches = code.length === manualCode.length && timingSafeEqual(Buffer.from(code, 'utf8'), Buffer.from(manualCode, 'utf8'));
        if (!tokenMatches && code) manualCodeAttempts += 1;
        if (Date.now() > expiresAt || (!tokenMatches && (!codeMatches || manualCodeAttempts > 5))) {
          log('pairing.rejected', { requestId, reason: Date.now() > expiresAt ? 'expired' : manualCodeAttempts > 5 ? 'manual-code-locked' : 'invalid-credential' });
          return json(response, 401, { error: 'Pairing credential is invalid, expired, or locked after too many attempts.' });
        }
        const deviceToken = await registry.issue(payload);
        log('pairing.succeeded', { requestId, deviceId: payload.deviceId, deviceName: payload.deviceName, credentialType: tokenMatches ? 'qr' : 'manual' });
        return json(response, 201, { protocol: 1, deviceToken });
      }
      if (!(await registry.valid(bearer(request)))) {
        log('request.rejected', { requestId, reason: 'unpaired-device' });
        return json(response, 401, { error: 'A paired-device token is required.' });
      }
      if (request.method === 'GET' && pathname === '/v1/snippets') {
        const snippets = await store.list();
        log('sync.pull.succeeded', { requestId, count: snippets.length });
        return json(response, 200, { snippets });
      }
      const snippetMatch = pathname.match(/^\/v1\/snippets\/([^/]+)$/);
      if (request.method === 'PUT' && snippetMatch) {
        const snippet = snippetSchema.parse(await body(request));
        const id = decodeURIComponent(snippetMatch[1]);
        if (id !== snippet.id) {
          log('sync.push.rejected', { requestId, reason: 'id-mismatch' });
          return json(response, 400, { error: 'Snippet ID must match the request path.' });
        }
        const saved: Snippet = await store.upsert(snippet);
        log('sync.push.succeeded', { requestId, snippetId: saved.id });
        return json(response, 200, { snippet: saved });
      }
      if (request.method === 'DELETE' && snippetMatch) {
        const id = decodeURIComponent(snippetMatch[1]);
        await store.remove(id);
        log('sync.delete.succeeded', { requestId, snippetId: id });
        return json(response, 204, {});
      }
      log('request.rejected', { requestId, reason: 'route-not-found' });
      return json(response, 404, { error: 'Route not found.' });
    } catch (error) {
      log('request.failed', { requestId, errorType: error instanceof Error ? error.name : typeof error });
      return json(response, 400, { error: error instanceof Error ? error.message : 'Invalid request.' });
    }
  });
  await new Promise<void>((resolve, reject) => { server.once('error', reject); server.listen(port, host, () => resolve()); });
  const pairingUri = `float://pair?url=${encodeURIComponent(agentUrl)}&token=${encodeURIComponent(oneTimeToken)}&v=1`;
  console.log(`Float paired-device agent listening at ${agentUrl}`);
  log('agent.started', { agentUrl, host, port, dataPath: process.env.FLOAT_HOME ?? join(homedir(), '.float') });
  log('pairing.registry.restored', { pairedDeviceCount: restoredDeviceCount });
  console.log('Scan this QR code in Float within 10 minutes. Keep this terminal open while syncing.');
  qrcode.generate(pairingUri, { small: true });
  console.log(`Pairing code: ${pairingUri}`);
  console.log(`Manual pairing: ${agentUrl}  •  code ${manualCode}`);
  if (options.durationSeconds) setTimeout(() => server.close(), options.durationSeconds * 1000).unref();
  await new Promise<void>((resolve) => server.once('close', resolve));
}
