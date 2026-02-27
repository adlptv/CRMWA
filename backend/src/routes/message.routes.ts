import { Router } from 'express';
import { sendMessage, getConversation, getChats, sendMessageValidation } from '../controllers/message.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();

router.use(authMiddleware);

router.post('/send', sendMessageValidation, sendMessage);
router.get('/conversation/:leadId', getConversation);
router.get('/chats', getChats);

export default router;
