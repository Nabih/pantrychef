# Build the React client, then serve it from Caddy alongside the API.
FROM node:22-alpine AS build

WORKDIR /app

COPY web/package*.json ./
RUN npm ci

COPY web/ ./
RUN npm run build

FROM caddy:2-alpine

COPY --from=build /app/dist /srv
COPY deploy/Caddyfile /etc/caddy/Caddyfile
