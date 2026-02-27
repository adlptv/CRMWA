import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import dotenv from 'dotenv';

dotenv.config();

import authRoutes from './routes/auth.routes';
import leadRoutes from './routes/lead.routes';
import messageRoutes from './routes/message.routes';
import blastRoutes from './routes/blast.routes';
import dashboardRoutes from './routes/dashboard.routes';
import webhookRoutes from './routes/webhook.routes';
import whatsappRoutes from './routes/whatsapp.routes';
import { errorHandler } from './middleware/error.middleware';
import { prisma } from './config/database';
import { waGatewayService } from './services/wa-gateway.service';
import { whatsAppWebService } from './services/whatsapp-web.service';

const app = express();
const PORT = process.env.PORT || 3000;

const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000'),
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '100'),
  message: { error: 'Too many requests, please try again later.' },
});

app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  credentials: true,
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

app.use('/api/auth', authRoutes);
app.use('/api/leads', leadRoutes);
app.use('/api/messages', messageRoutes);
app.use('/api/blast', blastRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/webhook', webhookRoutes);
app.use('/api/whatsapp', whatsappRoutes);

app.use('/api/', limiter);

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.use(errorHandler);

const gracefulShutdown = async () => {
  console.log('Received shutdown signal. Closing connections...');
  await prisma.$disconnect();
  await whatsAppWebService.destroy();
  process.exit(0);
};

process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);

app.listen(PORT, async () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
  
  // Initialize WhatsApp Web Service
  console.log('Initializing WhatsApp Web Service...');
  try {
    await whatsAppWebService.initialize();
  } catch (error) {
    console.error('Failed to initialize WhatsApp Web Service:', error);
  }
  
  // Initialize WhatsApp gateway
  console.log('WhatsApp Gateway:', waGatewayService.getStatus());
});

export default app;
