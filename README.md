# Deploy and Host Evolution API on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/evolution?referralCode=sLjDXb&utm_medium=integration&utm_source=button&utm_campaign=evolution)

[Evolution API](https://github.com/EvolutionAPI/evolution-api) is an open-source REST API for WhatsApp: pair a number by QR code, then send and receive messages, media and group events over HTTP and webhooks. This template runs the official v2 release with Postgres and Redis, set up so a paired number stays paired through restarts and redeploys.

## About Hosting Evolution API

The stack is three services: Evolution API, Postgres and Redis. Only Evolution API has a public URL.

- **Paired numbers survive restarts.** Evolution API keeps the instance credentials in Postgres and WhatsApp's encryption keys in Redis. If Redis loses its data, messages can fail to decrypt and the number may need pairing again. Here Redis writes every change to a volume and never evicts keys, and the API doesn't start until Redis answers.
- **Database and Redis stay private.** Neither has a public proxy. They are reachable only from your project's private network.
- **A pinned release.** Evolution API v2.3.7 in an image built once per release, with fixed Postgres and Redis versions, so a redeploy never pulls in an untested upgrade.
- **Starts in the right order.** The API waits for Postgres, applies its migrations, waits for Redis, then starts. If the API process dies it is restarted in place.
- **No default key.** The upstream image contains a public default API key. This template generates a private one and refuses to start if the key is empty or the default.
- **Fits a small plan.** Tested with every service limited to 0.5 GB: the API used about 250 MB with one instance, Postgres 80 MB and Redis 20 MB. Usage grows with the number of paired numbers and their traffic.

## Common Use Cases

- Send order updates, reminders and one-time codes from your own backend
- Connect WhatsApp to a CRM, help desk or chatbot through webhooks (n8n, Chatwoot, Typebot and Dify integrations are built in)
- Run several WhatsApp numbers from one server, each as its own instance

## Dependencies for Evolution API Hosting

- Postgres 18, included, with a volume
- Redis 8, included, with a volume

### Deployment Dependencies

- [Evolution API](https://github.com/EvolutionAPI/evolution-api) and its [documentation](https://doc.evolution-api.com)
- [API reference (Postman)](https://www.postman.com/agenciadgcode/evolution-api/overview)
- [Source of this template](https://github.com/two-workspaces/evolution)

### Implementation Details

**First steps.** Open the Evolution API service, copy `AUTHENTICATION_API_KEY` from its Variables tab, and use your public URL in place of `https://your-app.up.railway.app`.

Sign in to the manager UI at `/manager` with that key, or use the API:

```bash
# 1. Create an instance. The response holds the QR code as a base64 PNG.
curl -X POST https://your-app.up.railway.app/instance/create \
  -H "apikey: YOUR_API_KEY" -H "Content-Type: application/json" \
  -d '{"instanceName": "main", "integration": "WHATSAPP-BAILEYS", "qrcode": true}'

# 2. Scan the QR code in WhatsApp (Linked devices), then check the state.
curl https://your-app.up.railway.app/instance/connectionState/main -H "apikey: YOUR_API_KEY"

# 3. Send a message. The number is in international format, digits only.
curl -X POST https://your-app.up.railway.app/message/sendText/main \
  -H "apikey: YOUR_API_KEY" -H "Content-Type: application/json" \
  -d '{"number": "15551234567", "text": "Hello from Evolution API"}'

# 4. Receive messages on your own URL.
curl -X POST https://your-app.up.railway.app/webhook/set/main \
  -H "apikey: YOUR_API_KEY" -H "Content-Type: application/json" \
  -d '{"webhook": {"enabled": true, "url": "https://example.com/hook", "events": ["MESSAGES_UPSERT", "CONNECTION_UPDATE"]}}'
```

A new QR code is at `GET /instance/connect/main` if the first one expires.

**Variables you may want to set**

| Variable | What it does |
| --- | --- |
| `MESSAGE_RETENTION_DAYS` | Empty by default: messages are kept for good. Set a number of days and older saved messages are deleted every 6 hours, which keeps the Postgres volume from filling up. Chats, contacts and instances are never deleted. |
| `WEBHOOK_GLOBAL_ENABLED`, `WEBHOOK_GLOBAL_URL` | Send the events of every instance to one URL. |
| `DATABASE_SAVE_DATA_HISTORIC` | Set to `false` to skip saving the chat history WhatsApp sends when a number is paired. |
| `TZ` | Time zone for logs and timestamps. Default `UTC`. |
| `TELEMETRY_ENABLED` | Evolution API's usage telemetry. Off in this template. |

Every other [Evolution API variable](https://github.com/EvolutionAPI/evolution-api/blob/2.3.7/.env.example) works as a service variable.

**Media storage.** S3 is off, so media is delivered through webhooks and the API but not stored. For stored media, set `S3_ENABLED=true` with `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET` and `S3_REGION` for an S3-compatible store that allows listing buckets.

**Upgrading.** The template is updated when a new stable Evolution API release has been tested. To upgrade an existing deployment, change the image tag of the Evolution API service; migrations run on start.

**Good to know.** Evolution API uses WhatsApp Web's protocol through the Baileys library. It is not affiliated with WhatsApp or Meta, and WhatsApp can restrict numbers that send bulk or unsolicited messages. For the official channel, Evolution API also supports the WhatsApp Business Cloud API as an integration.

## Why Deploy Evolution API on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Evolution API on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
