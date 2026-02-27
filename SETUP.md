# CRM + WhatsApp Gateway - Setup Instructions

## Prerequisites

- Node.js 20+
- PostgreSQL 16+
- npm or yarn

## Quick Start

### 1. Clone and Setup Environment

```bash
cd laravel-crm

# Copy environment files
cp .env.example .env
cp backend/.env.example backend/.env
```

### 2. Configure Database

Edit `backend/.env`:
```
DATABASE_URL="postgresql://user:password@localhost:5432/crm_db?schema=public"
```

Create PostgreSQL database:
```sql
CREATE DATABASE crm_db;
```

### 3. Install Dependencies

```bash
# Backend
cd backend
npm install

# Frontend
cd ../frontend
npm install
```

### 4. Setup Database

```bash
cd backend

# Generate Prisma client
npm run prisma:generate

# Run migrations
npm run prisma:migrate

# Seed database with sample data
npm run db:seed
```

### 5. Start Development Servers

Terminal 1 (Backend):
```bash
cd backend
npm run dev
```

Terminal 2 (Frontend):
```bash
cd frontend
npm run dev
```

Access the application at http://localhost:5173

## Default Credentials

- Admin: admin@crm.com / admin123
- Sales 1: sales1@crm.com / sales123
- Sales 2: sales2@crm.com / sales123

## Production Deployment

### Using Docker

```bash
# Build and run
docker-compose up -d

# Run migrations
docker-compose exec backend npx prisma migrate deploy
```

### Manual Deployment

1. Build backend:
```bash
cd backend
npm run build
npm run prisma:generate
```

2. Build frontend:
```bash
cd frontend
npm run build
```

3. Serve backend with process manager (PM2):
```bash
pm2 start dist/index.js --name crm-backend
```

4. Serve frontend with nginx or similar.

## Environment Variables

### Backend (.env)

| Variable | Description | Default |
|----------|-------------|---------|
| PORT | Server port | 3000 |
| NODE_ENV | Environment | development |
| DATABASE_URL | PostgreSQL connection string | Required |
| JWT_SECRET | JWT signing secret | Required |
| JWT_EXPIRES_IN | JWT expiration | 7d |
| WA_GATEWAY_TYPE | Gateway type (cloud_api/web_automation/mock) | mock |
| WA_CLOUD_API_TOKEN | WhatsApp Cloud API token | - |
| WA_CLOUD_API_PHONE_ID | WhatsApp Phone Number ID | - |
| WA_WEBHOOK_SECRET | Webhook secret | - |
| WA_WEBHOOK_VERIFY_TOKEN | Webhook verify token | - |
| RATE_LIMIT_WINDOW_MS | Rate limit window | 900000 |
| RATE_LIMIT_MAX_REQUESTS | Max requests per window | 100 |
| MESSAGE_THROTTLE_MS | Message throttle delay | 2000 |
| CORS_ORIGIN | CORS origin | * |

### Frontend (.env)

| Variable | Description | Default |
|----------|-------------|---------|
| VITE_API_URL | Backend API URL | /api |

## WhatsApp Integration

### WhatsApp Cloud API

1. Create Meta Business account
2. Set up WhatsApp Business API
3. Configure webhook in Meta dashboard:
   - URL: `https://your-domain.com/api/webhook/whatsapp`
   - Verify token: Set in `WA_WEBHOOK_VERIFY_TOKEN`
4. Add credentials to `.env`:
   ```
   WA_GATEWAY_TYPE=cloud_api
   WA_CLOUD_API_TOKEN=your_token
   WA_CLOUD_API_PHONE_ID=your_phone_id
   WA_WEBHOOK_SECRET=your_secret
   WA_WEBHOOK_VERIFY_TOKEN=your_verify_token
   ```

### Web Automation Gateway

For custom WhatsApp automation:
1. Set `WA_GATEWAY_TYPE=web_automation`
2. Implement your automation to POST to `/api/webhook/custom`
3. Include `X-Webhook-Secret` header

## Project Structure

```
laravel-crm/
├── backend/
│   ├── src/
│   │   ├── config/         # Configuration
│   │   ├── controllers/    # Request handlers
│   │   ├── middleware/     # Express middleware
│   │   ├── routes/         # API routes
│   │   ├── services/       # Business logic
│   │   ├── utils/          # Utilities
│   │   └── index.ts        # Entry point
│   ├── prisma/
│   │   ├── schema.prisma   # Database schema
│   │   └── seed.ts         # Seed data
│   └── package.json
├── frontend/
│   ├── src/
│   │   ├── components/     # React components
│   │   ├── contexts/       # React contexts
│   │   ├── hooks/          # Custom hooks
│   │   ├── layouts/        # Page layouts
│   │   ├── pages/          # Page components
│   │   ├── services/       # API services
│   │   ├── utils/          # Utilities
│   │   ├── App.tsx         # App component
│   │   └── main.tsx        # Entry point
│   └── package.json
├── docker-compose.yml
├── Dockerfile
└── API_DOCS.md
```

## Troubleshooting

### Database Connection Error
- Verify PostgreSQL is running
- Check DATABASE_URL format
- Ensure database exists

### JWT Invalid Error
- Clear localStorage
- Re-login
- Verify JWT_SECRET is consistent

### WhatsApp Not Working
- Check WA_GATEWAY_TYPE
- Verify Cloud API credentials
- Check webhook configuration
