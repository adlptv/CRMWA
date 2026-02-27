import { Router } from 'express';
import {
  createLead,
  getLead,
  getLeads,
  updateLead,
  deleteLead,
  getLeadStats,
  createLeadValidation,
  updateLeadValidation,
} from '../controllers/lead.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();

router.use(authMiddleware);

router.post('/', createLeadValidation, createLead);
router.get('/stats', getLeadStats);
router.get('/', getLeads);
router.get('/:id', getLead);
router.put('/:id', updateLeadValidation, updateLead);
router.delete('/:id', deleteLead);

export default router;
