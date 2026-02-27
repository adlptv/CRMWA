import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { prisma } from '../config/database';
import { AppError } from './error.middleware';
import { config } from '../config';

export interface AuthRequest extends Request {
  user?: {
    id: string;
    email: string;
    role: string;
  };
}

export const authMiddleware = async (
  req: AuthRequest,
  _res: Response,
  next: NextFunction
) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new AppError(401, 'No token provided');
    }

    const token = authHeader.split(' ')[1];
    
    const decoded = jwt.verify(token, config.jwt.secret) as { id: string };
    
    const user = await prisma.user.findUnique({
      where: { id: decoded.id },
      select: { id: true, email: true, role: true, isActive: true },
    });

    if (!user || !user.isActive) {
      throw new AppError(401, 'Invalid or inactive user');
    }

    req.user = user;
    next();
  } catch (error) {
    if (error instanceof jwt.JsonWebTokenError) {
      next(new AppError(401, 'Invalid token'));
    } else {
      next(error);
    }
  }
};

export const requireAdmin = (
  req: AuthRequest,
  _res: Response,
  next: NextFunction
) => {
  if (req.user?.role !== 'ADMIN') {
    return next(new AppError(403, 'Admin access required'));
  }
  next();
};

export const requireAdminOrAssigned = async (
  req: AuthRequest,
  _res: Response,
  next: NextFunction
) => {
  if (req.user?.role === 'ADMIN') {
    return next();
  }
  
  const leadId = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
  if (leadId) {
    const lead = await prisma.lead.findUnique({
      where: { id: leadId },
      select: { assignedTo: true },
    });
    
    if (lead && lead.assignedTo === req.user?.id) {
      return next();
    }
  }
  
  next(new AppError(403, 'Access denied'));
};
