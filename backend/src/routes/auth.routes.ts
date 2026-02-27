import { Router } from 'express';
import { register, login, getProfile, getAllUsers, updateUser, changePassword, registerValidation, loginValidation } from '../controllers/auth.controller';
import { authMiddleware, requireAdmin } from '../middleware/auth.middleware';

const router = Router();

router.post('/register', registerValidation, register);
router.post('/login', loginValidation, login);
router.get('/profile', authMiddleware, getProfile);
router.put('/password', authMiddleware, changePassword);

router.get('/users', authMiddleware, requireAdmin, getAllUsers);
router.put('/users/:id', authMiddleware, requireAdmin, updateUser);

export default router;
