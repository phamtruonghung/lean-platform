# syntax=docker/dockerfile:1

FROM node:22-alpine

ENV NODE_ENV=production

WORKDIR /app

# Copy the manifests first so this layer is cached until dependencies change.
COPY package.json package-lock.json ./

# `npm ci` installs exactly what the lockfile specifies, so a build today and a
# rebuild in six months produce the same dependency tree. `npm install` does not
# guarantee that.
RUN npm ci --omit=dev && npm cache clean --force

COPY src ./src
COPY migrations ./migrations

# Run as an unprivileged user. Setting it here means `docker run` locally
# behaves the same way as the deployment does.
RUN addgroup -g 10001 -S app && adduser -u 10001 -S -G app -h /home/app app
USER 10001:10001

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.BACKEND_PORT||8000)+'/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# Exec form, invoking node directly rather than through npm. This makes node
# PID 1, so it receives SIGTERM on shutdown and can close connections cleanly.
# Running via `npm start` swallows the signal.
CMD ["node", "src/index.js"]
