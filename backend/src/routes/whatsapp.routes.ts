import { Router } from 'express';
import { authMiddleware } from '../middleware/auth.middleware';
import { whatsAppWebService } from '../services/whatsapp-web.service';

const router = Router();

// Get WhatsApp connection status
router.get('/status', authMiddleware, (_req, res) => {
  const status = whatsAppWebService.getStatus();
  res.json(status);
});

// Get all WhatsApp chats (groups + private)
router.get('/chats', authMiddleware, async (_req, res, next) => {
  try {
    const chats = await whatsAppWebService.getAllChats();
    res.json(chats);
  } catch (error) {
    next(error);
  }
});

// Get all WhatsApp contacts
router.get('/contacts', authMiddleware, async (_req, res, next) => {
  try {
    const contacts = await whatsAppWebService.getContacts();
    res.json(contacts);
  } catch (error) {
    next(error);
  }
});

// Get messages from a specific chat
router.get('/chats/:chatId/messages', authMiddleware, async (req, res, next) => {
  try {
    const chatId = Array.isArray(req.params.chatId) ? req.params.chatId[0] : req.params.chatId;
    const limitParam = Array.isArray(req.query.limit) ? req.query.limit[0] : req.query.limit;
    const limit = parseInt(String(limitParam || '50')) || 50;
    const messages = await whatsAppWebService.getChatMessages(chatId, limit);
    res.json(messages);
  } catch (error) {
    next(error);
  }
});

// Send message to a chat (private or group)
router.post('/send', authMiddleware, async (req, res, next) => {
  try {
    const { to, message } = req.body;
    
    if (!to || !message) {
      return res.status(400).json({ error: 'to and message are required' });
    }

    // Determine if it's a group or private chat
    const isGroup = to.includes('@g.us') || req.body.isGroup;
    
    let result;
    if (isGroup) {
      result = await whatsAppWebService.sendGroupMessage(to, message);
    } else {
      result = await whatsAppWebService.sendMessage(to, message);
    }

    if (result.success) {
      res.json({ success: true, messageId: result.messageId });
    } else {
      res.status(500).json({ error: result.error });
    }
  } catch (error) {
    next(error);
  }
});

export default router;
