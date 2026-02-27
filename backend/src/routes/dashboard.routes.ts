import { Router } from 'express';
import { getDashboard, getRecentLeads, getRecentMessages } from '../controllers/dashboard.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();

router.use(authMiddleware);

router.get('/', getDashboard);
router.get('/recent-leads', getRecentLeads);
router.get('/recent-messages', getRecentMessages);

export default router;
