# The internal docs site (docs.{$BASE_DOMAIN}, behind Caddy's basic_auth).
# Build context is the META REPO ROOT: the site reads ../docs in place.
#   docker build -f docs-site/Dockerfile -t docs-site .
# Dockerfile.dockerignore (next to this file) lets in only docs/ and docs-site/.
FROM node:22.21.1-alpine AS build
WORKDIR /repo/docs-site
RUN corepack enable && corepack prepare pnpm@10.28.0 --activate
COPY docs-site/package.json docs-site/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY docs /repo/docs
COPY docs-site/ ./
RUN pnpm build

# ── Production: the static build behind nginx (Caddy is the edge) ──
FROM nginx:1.29.3-alpine AS production
COPY docs-site/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /repo/docs-site/dist /usr/share/nginx/html
EXPOSE 80
