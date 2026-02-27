import { body, validationResult } from 'express-validator';
import { NextFunction, Request, Response } from 'express';
import { blastService } from '../services/blast.service';
import { AppError } from '../middleware/error.middleware';
import { AuthRequest } from '../middleware/auth.middleware';

export const createBlastValidation = [
  body('name').trim().notEmpty().withMessage('Name is required'),
  body('message').trim().notEmpty().withMessage('Message is required'),
  body('leadIds').isArray({ min: 1 }).withMessage('At least one lead ID is required'),
];

export const createBlast = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      throw new AppError(400, errors.array()[0].msg);
    }

    const { name, message, leadIds } = req.body;
    const userId = req.user?.id;
    if (!userId) {
      throw new AppError(401, 'Not authenticated');
    }

    const blast = await blastService.createBlast(
      { name, message, leadIds },
      userId
    );

    res.status(201).json(blast);
  } catch (error) {
    next(error);
  }
};

export const startBlast = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const id = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;

    const result = await blastService.startBlast(id);

    res.json(result);
  } catch (error) {
    next(error);
  }
};

export const getAllBlasts = async (_req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const blasts = await blastService.getAllBlasts();

    res.json(blasts);
  } catch (error) {
    next(error);
  }
};

export const getBlastById = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const id = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;

    const blast = await blastService.getBlastById(id);

    res.json(blast);
  } catch (error) {
    next(error);
  }
};
