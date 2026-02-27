# CRM + WhatsApp Gateway API Documentation

Base URL: `http://localhost:3000/api`

## Authentication

All protected endpoints require Bearer token in Authorization header.

```
Authorization: Bearer <token>
```

---

## Auth Endpoints

### POST /auth/register

Register a new user (Admin only).

**Request Body:**
```json
{
  "name": "string",
  "email": "string",
  "password": "string (min 6 chars)",
  "role": "ADMIN" | "SALES"
}
```

**Response:**
```json
{
  "id": "uuid",
  "name": "string",
  "email": "string",
  "role": "ADMIN" | "SALES",
  "createdAt": "ISO date"
}
```

### POST /auth/login

Authenticate user.

**Request Body:**
```json
{
  "email": "string",
  "password": "string"
}
```

**Response:**
```json
{
  "user": {
    "id": "uuid",
    "name": "string",
    "email": "string",
    "role": "ADMIN" | "SALES"
  },
  "token": "jwt_token"
}
```

### GET /auth/profile

Get current user profile. (Protected)

**Response:**
```json
{
  "id": "uuid",
  "name": "string",
  "email": "string",
  "role": "ADMIN" | "SALES",
  "createdAt": "ISO date"
}
```

### PUT /auth/password

Change password. (Protected)

**Request Body:**
```json
{
  "currentPassword": "string",
  "newPassword": "string (min 6 chars)"
}
```

### GET /auth/users

Get all users. (Admin only)

### PUT /auth/users/:id

Update user. (Admin only)

**Request Body:**
```json
{
  "name": "string",
  "isActive": boolean
}
```

---

## Lead Endpoints

### GET /leads

Get all leads with optional filters. (Protected)

**Query Parameters:**
- `status` - NEW, FOLLOW_UP, DEAL, CANCEL
- `source` - ORGANIC, IG, OTHER
- `assignedTo` - user UUID
- `dateFrom` - ISO date
- `dateTo` - ISO date
- `search` - search by name or phone

**Response:**
```json
[
  {
    "id": "uuid",
    "name": "string",
    "phone": "string",
    "source": "ORGANIC" | "IG" | "OTHER",
    "status": "NEW" | "FOLLOW_UP" | "DEAL" | "CANCEL",
    "notes": "string",
    "assignedTo": "uuid",
    "createdAt": "ISO date",
    "updatedAt": "ISO date",
    "assignedUser": {
      "id": "uuid",
      "name": "string",
      "email": "string"
    }
  }
]
```

### GET /leads/stats

Get lead statistics. (Protected)

**Query Parameters:**
- `dateFrom` - ISO date
- `dateTo` - ISO date

**Response:**
```json
{
  "total": number,
  "new": number,
  "followUp": number,
  "deal": number,
  "cancel": number
}
```

### GET /leads/:id

Get lead by ID with messages. (Protected)

### POST /leads

Create new lead. (Protected)

**Request Body:**
```json
{
  "name": "string",
  "phone": "string",
  "source": "ORGANIC" | "IG" | "OTHER",
  "notes": "string",
  "assignedTo": "uuid"
}
```

### PUT /leads/:id

Update lead. (Protected)

**Request Body:**
```json
{
  "name": "string",
  "phone": "string",
  "source": "ORGANIC" | "IG" | "OTHER",
  "status": "NEW" | "FOLLOW_UP" | "DEAL" | "CANCEL",
  "notes": "string",
  "assignedTo": "uuid" | null
}
```

### DELETE /leads/:id

Delete lead. (Admin only)

---

## Message Endpoints

### GET /messages/chats

Get chat list. (Protected)

**Query Parameters:**
- `phone` - filter by phone

### GET /messages/conversation/:leadId

Get conversation messages for a lead. (Protected)

### POST /messages/send

Send message to lead. (Protected)

**Request Body:**
```json
{
  "leadId": "uuid",
  "message": "string"
}
```

**Response:**
```json
{
  "id": "uuid",
  "leadId": "uuid",
  "phone": "string",
  "direction": "OUTBOUND",
  "message": "string",
  "timestamp": "ISO date",
  "handledBy": "uuid"
}
```

---

## WA Blast Endpoints (Admin only)

### GET /blast

Get all blast tasks.

### GET /blast/:id

Get blast task by ID with logs.

### POST /blast

Create blast task.

**Request Body:**
```json
{
  "name": "string",
  "message": "string",
  "leadIds": ["uuid", "uuid"]
}
```

### POST /blast/:id/start

Start processing blast task.

---

## Dashboard Endpoints

### GET /dashboard

Get dashboard statistics. (Protected)

**Query Parameters:**
- `dateFrom` - ISO date
- `dateTo` - ISO date

**Response (Admin):**
```json
{
  "leads": {
    "total": number,
    "new": number,
    "followUp": number,
    "deal": number,
    "cancel": number
  },
  "messages": {
    "total": number,
    "inbound": number,
    "outbound": number
  },
  "sales": [
    {
      "id": "uuid",
      "name": "string",
      "totalLeads": number,
      "dealCount": number,
      "conversionRate": number
    }
  ]
}
```

### GET /dashboard/recent-leads

Get recent leads. (Protected)

### GET /dashboard/recent-messages

Get recent messages. (Protected)

---

## Webhook Endpoints

### GET /webhook/whatsapp

WhatsApp Cloud API webhook verification.

**Query Parameters:**
- `hub.mode` - should be "subscribe"
- `hub.verify_token` - verification token
- `hub.challenge` - challenge string to return

### POST /webhook/whatsapp

WhatsApp Cloud API webhook for incoming messages.

**Headers:**
- `X-Hub-Signature-256` - webhook signature

### POST /webhook/custom

Custom webhook for incoming messages (for web automation gateway).

**Headers:**
- `X-Webhook-Secret` - webhook secret

**Request Body:**
```json
{
  "phone": "string",
  "message": "string"
}
```

---

## Error Responses

All errors return:
```json
{
  "error": "Error message"
}
```

Common HTTP status codes:
- 400 - Bad Request
- 401 - Unauthorized
- 403 - Forbidden
- 404 - Not Found
- 500 - Internal Server Error

---

## Rate Limiting

API endpoints are rate limited to 100 requests per 15 minutes by default.
