import { Router } from 'express';
import { verifyWebhook, handleWebhook, handleCustomWebhook } from '../controllers/webhook.controller';

const router = Router();

router.get('/whatsapp', verifyWebhook);
router.post('/whatsapp', handleWebhook);
router.post('/custom', handleCustomWebhook);

export default router;
