# syntax=docker/dockerfile:1

# ---- build stage: compile TypeScript ----
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# ---- deps stage: production-only node_modules ----
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

# ---- runtime stage: minimal, non-root ----
FROM node:20-alpine AS runtime
ENV NODE_ENV=production
ENV PORT=8080
WORKDIR /app
RUN addgroup -S nodejs && adduser -S nodejs -G nodejs
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
EXPOSE 8080
USER nodejs
CMD ["node", "dist/server.js"]
