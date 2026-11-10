# Evolution API for Railway: the upstream release, unmodified, behind a start script that
# waits for Postgres and Redis, refuses the image's public default API key and restarts
# the API if it dies. Built by .github/workflows/image.yml; Railway pulls the finished image.
FROM evoapicloud/evolution-api:v2.3.7@sha256:1bd8afc4a6cf48822e6cf02469aeae7bd35a12a6b616eacd1291926307f4d339

RUN apk add --no-cache tini

# Constant settings live here; secrets and service references are template variables.
# Every one of these can be overridden with a service variable.
# - WhatsApp's encryption keys are kept in Redis (CACHE_REDIS_ENABLED) and the instance
#   credentials in Postgres (DATABASE_SAVE_DATA_INSTANCE). Both must be durable.
# - S3 is off: Evolution's minio client lists and creates buckets at boot, which Railway's
#   single-bucket credentials can't do. Set S3_ENABLED=true with S3_ENDPOINT, S3_ACCESS_KEY,
#   S3_SECRET_KEY, S3_BUCKET and S3_REGION to use external S3-compatible storage.
ENV TZ=UTC \
    SERVER_TYPE=http \
    LANGUAGE=en \
    LOG_LEVEL=ERROR,WARN,INFO,LOG,WEBHOOKS \
    LOG_COLOR=false \
    TELEMETRY_ENABLED=false \
    DEL_INSTANCE=false \
    DATABASE_PROVIDER=postgresql \
    DATABASE_CONNECTION_CLIENT_NAME=evolution \
    CACHE_REDIS_ENABLED=true \
    CACHE_REDIS_PREFIX_KEY=evolution \
    CACHE_REDIS_SAVE_INSTANCES=false \
    CACHE_LOCAL_ENABLED=false \
    S3_ENABLED=false

COPY railway/ /evolution/railway/
RUN chmod +x /evolution/railway/entrypoint.sh

# The manager UI loads its logo and favicon from evolution-api.com/files/evo/, which has
# answered 404 since 2026, so the top-left logo is a broken image. Serve them from this
# container instead: the upstream white logo (dark theme) and favicon, recovered unmodified
# from the Web Archive, and the PNG logo the image already ships (light theme).
# The build fails if a future release changes these URLs, so this can't silently stop working.
RUN cp /evolution/railway/branding/*.svg /evolution/manager/dist/assets/images/ \
 && cd /evolution/manager/dist \
 && grep -q "evolution-api.com/files/evo/evolution-logo" assets/*.js \
 && sed -i \
      -e 's#https://evolution-api.com/files/evo/evolution-logo-white.svg#/assets/images/evolution-logo-white.svg#g' \
      -e 's#https://evolution-api.com/files/evo/evolution-logo.svg#/assets/images/evolution-logo.png#g' \
      -e 's#type="image/png" href="https://evolution-api.com/files/evo/favicon.svg"#type="image/svg+xml" href="/assets/images/favicon.svg"#g' \
      index.html assets/*.js \
 && ! grep -q "evolution-api.com/files/evo" index.html assets/*.js

ENTRYPOINT ["/sbin/tini", "-g", "--", "/evolution/railway/entrypoint.sh"]
