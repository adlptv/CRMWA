import { Router } from 'express';
import { createBlast, startBlast, getAllBlasts, getBlastById, createBlastValidation } from '../controllers/blast.controller';
import { authMiddleware, requireAdmin } from '../middleware/auth.middleware';

const router = Router();

router.use(authMiddleware);
router.use(requireAdmin);

router.post('/', createBlastValidation, createBlast);
router.post('/:id/start', startBlast);
router.get('/', getAllBlasts);
router.get('/:id', getBlastById);

export default router;
