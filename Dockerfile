FROM node:20-alpine AS backend-builder

WORKDIR /app/backend

COPY backend/package*.json ./
RUN npm ci

COPY backend/tsconfig.json ./
COPY backend/prisma ./prisma/
RUN npx prisma generate

COPY backend/src ./src
RUN npm run build

FROM node:20-alpine AS frontend-builder

WORKDIR /app/frontend

COPY frontend/package*.json ./
RUN npm ci

COPY frontend/vite.config.ts frontend/tailwind.config.js frontend/postcss.config.js frontend/tsconfig.json frontend/index.html ./
COPY frontend/src ./src
COPY frontend/public ./public

RUN npm run build

FROM node:20-alpine

WORKDIR /app

COPY --from=backend-builder /app/backend/dist ./backend/dist
COPY --from=backend-builder /app/backend/node_modules ./backend/node_modules
COPY --from=backend-builder /app/backend/package.json ./backend/
COPY --from=backend-builder /app/backend/prisma ./backend/prisma

COPY --from=frontend-builder /app/frontend/dist ./frontend/dist

WORKDIR /app/backend

EXPOSE 3000

CMD ["node", "dist/index.js"]
