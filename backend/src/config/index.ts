export const config = {
  jwt: {
    secret: process.env.JWT_SECRET || 'default-secret-change-me',
    expiresIn: process.env.JWT_EXPIRES_IN || '7d',
  },
  wa: {
    gatewayType: process.env.WA_GATEWAY_TYPE || 'cloud_api',
    cloudApiToken: process.env.WA_CLOUD_API_TOKEN || '',
    cloudApiPhoneId: process.env.WA_CLOUD_API_PHONE_ID || '',
    webhookSecret: process.env.WA_WEBHOOK_SECRET || '',
    webhookVerifyToken: process.env.WA_WEBHOOK_VERIFY_TOKEN || '',
    facebookAppSecret: process.env.FACEBOOK_APP_SECRET || '',
    whatsappApiVersion: process.env.WHATSAPP_API_VERSION || 'v18.0',
  },
  messageThrottle: {
    ms: parseInt(process.env.MESSAGE_THROTTLE_MS || '2000'),
  },
  cors: {
    origin: process.env.CORS_ORIGIN || '*',
  },
};
