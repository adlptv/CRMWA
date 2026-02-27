import { body, validationResult } from 'express-validator';
import { NextFunction, Request, Response } from 'express';
import { authService } from '../services/auth.service';
import { AppError } from '../middleware/error.middleware';
import { AuthRequest } from '../middleware/auth.middleware';

export const registerValidation = [
  body('name').trim().notEmpty().withMessage('Name is required'),
  body('email').isEmail().normalizeEmail().withMessage('Valid email is required'),
  body('password').isLength({ min: 6 }).withMessage('Password must be at least 6 characters'),
  body('role').optional().isIn(['ADMIN', 'SALES']).withMessage('Invalid role'),
];

export const loginValidation = [
  body('email').isEmail().normalizeEmail().withMessage('Valid email is required'),
  body('password').notEmpty().withMessage('Password is required'),
];

export const register = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      throw new AppError(400, errors.array()[0].msg);
    }

    const { name, email, password, role } = req.body;
    const user = await authService.register(name, email, password, role);

    res.status(201).json({ user });
  } catch (error) {
    next(error);
  }
};

export const login = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      throw new AppError(400, errors.array()[0].msg);
    }

    const { email, password } = req.body;
    const result = await authService.login(email, password);

    res.json(result);
  } catch (error) {
    next(error);
  }
};

export const getProfile = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    if (!req.user) {
      throw new AppError(401, 'Not authenticated');
    }

    const user = await authService.getProfile(req.user.id);
    res.json(user);
  } catch (error) {
    next(error);
  }
};

export const getAllUsers = async (_req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const users = await authService.getAllUsers();
    res.json(users);
  } catch (error) {
    next(error);
  }
};

export const updateUser = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const id = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const name = typeof req.body.name === 'string' ? req.body.name : undefined;
    const isActive = typeof req.body.isActive === 'boolean' ? req.body.isActive : undefined;

    const user = await authService.updateUser(id, { name, isActive });
    res.json(user);
  } catch (error) {
    next(error);
  }
};

export const changePassword = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    if (!req.user) {
      throw new AppError(401, 'Not authenticated');
    }

    // Extract passwords and ensure they are strings
    const currentPassword: string = (() => {
      const val = req.body.currentPassword;
      if (Array.isArray(val)) return String(val[0] || '');
      return typeof val === 'string' ? val : '';
    })();
    const newPassword: string = (() => {
      const val = req.body.newPassword;
      if (Array.isArray(val)) return String(val[0] || '');
      return typeof val === 'string' ? val : '';
    })();
    
    if (!currentPassword || !newPassword) {
      throw new AppError(400, 'Current and new password are required');
    }

    if (newPassword.length < 6) {
      throw new AppError(400, 'New password must be at least 6 characters');
    }

    const result = await authService.changePassword(req.user.id, currentPassword, newPassword);
    res.json(result);
  } catch (error) {
    next(error);
  }
};
