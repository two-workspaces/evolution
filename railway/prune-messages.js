// Deletes saved messages older than MESSAGE_RETENTION_DAYS, with their status updates and
// media records (the database removes those through ON DELETE CASCADE). Off unless the
// variable is set. Chats, contacts, instances and settings are never touched.
const { PrismaClient } = require('@prisma/client');

(async () => {
  const days = parseInt(process.env.MESSAGE_RETENTION_DAYS || '', 10);
  if (!(days > 0)) return;
  const cutoff = Math.floor(Date.now() / 1000) - days * 86400;
  const prisma = new PrismaClient();
  let total = 0;
  try {
    for (;;) {
      const rows = await prisma.message.findMany({
        where: { messageTimestamp: { lt: cutoff } },
        select: { id: true },
        take: 2000,
      });
      if (!rows.length) break;
      const r = await prisma.message.deleteMany({ where: { id: { in: rows.map((x) => x.id) } } });
      total += r.count;
      if (!r.count) break;
    }
    console.log(`[railway] retention: deleted ${total} messages older than ${days} days`);
  } finally {
    await prisma.$disconnect();
  }
})().catch((e) => {
  console.error(`[railway] retention failed: ${e.message}`);
  process.exit(1);
});
