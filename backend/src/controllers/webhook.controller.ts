import { NextFunction, Request, Response } from 'express';
import { messageService } from '../services/message.service';
import { waGatewayService } from '../services/wa-gateway.service';
import { config } from '../config';
import { prisma } from '../config/database';

export const verifyWebhook = (req: Request, res: Response) => {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];

  console.log('Webhook verification request:', { mode, token, challenge });

  if (mode === 'subscribe' && waGatewayService.verifyWebhook(token as string)) {
    console.log('Webhook verified successfully');
    return res.status(200).send(challenge);
  }

  console.warn('Webhook verification failed');
  return res.status(403).send('Verification failed');
};

export const handleWebhook = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const signature = req.headers['x-hub-signature-256'] as string;
    
    // Get raw body for signature verification
    const rawBody = JSON.stringify(req.body);
    
    // Verify signature if app secret is configured
    if (config.wa.facebookAppSecret && signature) {
      if (!waGatewayService.verifySignature(rawBody, signature)) {
        console.warn('Invalid webhook signature');
        return res.status(401).json({ error: 'Invalid signature' });
      }
    }

    const processed = waGatewayService.processWebhook(req.body);

    if (!processed) {
      return res.status(200).json({ status: 'ignored' });
    }

    const { phone, message, messageId, contactName, messageType, status } = processed;

    // Handle status updates (sent, delivered, read, failed)
    if (status) {
      console.log(`Message ${messageId} status: ${status.status}`);
      
      // Update message status in database if we have a message ID
      if (messageId) {
        const existingMessage = await prisma.message.findFirst({
          where: { 
            OR: [
              { id: messageId },
              // Try to find by other identifiers if needed
            ]
          }
        });

        if (existingMessage) {
          // Could add status tracking fields to Message model
          console.log(`Updated status for message ${messageId}: ${status.status}`);
        }
      }
      
      return res.status(200).json({ 
        status: 'status_updated', 
        messageId,
        newStatus: status.status 
      });
    }

    // Handle incoming message
    const savedMessage = await messageService.handleIncomingMessage(phone, message);

    // Update lead name if we got a contact name from WhatsApp
    if (contactName && savedMessage.leadId) {
      await prisma.lead.update({
        where: { id: savedMessage.leadId },
        data: { name: contactName }
      });
    }

    console.log(`Incoming message from ${phone} (${contactName || 'Unknown'}): ${message}`);

    res.status(200).json({ 
      status: 'received', 
      leadId: savedMessage.leadId,
      messageId: savedMessage.id
    });
  } catch (error) {
    console.error('Webhook error:', error);
    next(error);
  }
};

export const handleCustomWebhook = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { phone, message } = req.body;

    if (!phone || !message) {
      return res.status(400).json({ error: 'Phone and message are required' });
    }

    const secret = req.headers['x-webhook-secret'];
    if (config.wa.webhookSecret && secret !== config.wa.webhookSecret) {
      return res.status(401).json({ error: 'Invalid webhook secret' });
    }

    const savedMessage = await messageService.handleIncomingMessage(phone, message);

    res.status(200).json({ 
      status: 'received', 
      leadId: savedMessage.leadId 
    });
  } catch (error) {
    next(error);
  }
};