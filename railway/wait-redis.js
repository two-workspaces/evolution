// Waits until Redis answers PING. WhatsApp's encryption keys live in Redis, and Evolution API
// treats a failed read as "no key", so it must not start before Redis is reachable.
const { createClient } = require('redis');

const url = process.env.CACHE_REDIS_URI;
const seconds = parseInt(process.env.REDIS_WAIT_SECONDS || '180', 10);
const log = (m) => console.log(`[railway] ${m}`);

(async () => {
  if (!url) {
    log('CACHE_REDIS_ENABLED is true but CACHE_REDIS_URI is not set. Point it at the Redis service, or set CACHE_REDIS_ENABLED=false and CACHE_LOCAL_ENABLED=true.');
    process.exit(1);
  }
  const deadline = Date.now() + seconds * 1000;
  let lastError = '';
  for (let attempt = 1; ; attempt++) {
    const client = createClient({ url, socket: { connectTimeout: 4000, reconnectStrategy: false } });
    client.on('error', (e) => { lastError = e.message || e.code || String(e); });
    try {
      await client.connect();
      await client.ping();
      await client.quit();
      log(`Redis is reachable (attempt ${attempt})`);
      return;
    } catch (e) {
      lastError = e.message || e.code || lastError;
      try { await client.disconnect(); } catch {}
    }
    if (Date.now() >= deadline) {
      log(`Redis did not answer within ${seconds}s: ${lastError}`);
      process.exit(1);
    }
    if (attempt === 1 || attempt % 6 === 0) log(`Redis isn't reachable yet (${lastError}), retrying`);
    await new Promise((r) => setTimeout(r, 3000));
  }
})();
