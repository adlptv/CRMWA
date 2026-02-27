import { config } from '../config';
import { whatsAppWebService } from './whatsapp-web.service';

interface SendMessageResult {
  success: boolean;
  messageId?: string;
  error?: string;
}

interface WebhookPayload {
  phone: string;
  message: string;
  messageId?: string;
  contactName?: string;
  messageType?: string;
  mediaId?: string;
  status?: {
    id: string;
    status: string;
    timestamp: string;
  };
}

class WAGatewayService {
  private gatewayType: string;

  constructor() {
    this.gatewayType = config.wa.gatewayType;
    
    // Initialize WhatsApp Web if that's the selected gateway
    if (this.gatewayType === 'web_automation') {
      this.initializeWhatsAppWeb();
    }
  }

  private async initializeWhatsAppWeb(): Promise<void> {
    try {
      console.log('Initializing WhatsApp Web gateway...');
      await whatsAppWebService.initialize();
    } catch (error) {
      console.error('Failed to initialize WhatsApp Web:', error);
    }
  }

  async sendMessage(to: string, message: string): Promise<SendMessageResult> {
    const sanitizedMessage = this.sanitizeMessage(message);
    const sanitizedPhone = to.replace(/\D/g, '');

    switch (this.gatewayType) {
      case 'web_automation':
        return await whatsAppWebService.sendMessage(sanitizedPhone, sanitizedMessage);
      
      case 'cloud_api':
        return await this.sendViaCloudApi(sanitizedPhone, sanitizedMessage);
      
      case 'mock':
      default:
        console.log(`[Mock] Sending to ${sanitizedPhone}: ${sanitizedMessage}`);
        return { success: true, messageId: `mock_${Date.now()}` };
    }
  }

  private async sendViaCloudApi(to: string, message: string): Promise<SendMessageResult> {
    try {
      const token = config.wa.cloudApiToken;
      const phoneId = config.wa.cloudApiPhoneId;
      const apiVersion = config.wa.whatsappApiVersion || 'v18.0';

      if (!token || !phoneId) {
        return { success: false, error: 'WhatsApp Cloud API not configured' };
      }

      const response = await fetch(
        `https://graph.facebook.com/${apiVersion}/${phoneId}/messages`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            messaging_product: 'whatsapp',
            recipient_type: 'individual',
            to: to,
            type: 'text',
            text: { body: message },
          }),
        }
      );

      const data = await response.json() as any;

      if (!response.ok) {
        const errorMsg = data.error?.message || data.error?.error_user_msg || 'Failed to send message';
        console.error('WhatsApp API error:', data.error);
        return { success: false, error: errorMsg };
      }

      return { success: true, messageId: data.messages?.[0]?.id };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  verifyWebhook(token: string): boolean {
    return token === config.wa.webhookVerifyToken;
  }

  verifySignature(_body: string, _signature: string): boolean {
    // For web_automation mode, we don't need signature verification
    // This is only needed for Cloud API webhooks
    return true;
  }

  processWebhook(_body: any): WebhookPayload | null {
    // For web_automation mode, messages are handled directly by whatsapp-web.js
    // This is only needed for Cloud API webhooks
    return null;
  }

  isConnected(): boolean {
    if (this.gatewayType === 'web_automation') {
      return whatsAppWebService.isConnected();
    }
    return true;
  }

  getStatus(): { gateway: string; connected: boolean; message: string } {
    if (this.gatewayType === 'web_automation') {
      const status = whatsAppWebService.getStatus();
      return { gateway: 'web_automation', connected: status.connected, message: status.message };
    }
    if (this.gatewayType === 'cloud_api') {
      return { gateway: 'cloud_api', connected: true, message: 'Cloud API configured' };
    }
    return { gateway: 'mock', connected: true, message: 'Mock mode active' };
  }

  private sanitizeMessage(message: string): string {
    return message
      .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '')
      .replace(/javascript:/gi, '')
      .replace(/on\w+=/gi, '')
      .trim();
  }
}

export const waGatewayService = new WAGatewayService();
