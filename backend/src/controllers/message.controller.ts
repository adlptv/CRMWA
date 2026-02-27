import { body, validationResult } from 'express-validator';
import { NextFunction, Request, Response } from 'express';
import { messageService } from '../services/message.service';
import { AppError } from '../middleware/error.middleware';
import { AuthRequest } from '../middleware/auth.middleware';

export const sendMessageValidation = [
  body('leadId').isUUID().withMessage('Valid lead ID is required'),
  body('message').trim().notEmpty().withMessage('Message is required'),
];

export const sendMessage = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      throw new AppError(400, errors.array()[0].msg);
    }

    const { leadId, message } = req.body;
    const userId = req.user?.id || '';

    const result = await messageService.sendMessage(leadId, message, userId);

    res.json(result);
  } catch (error) {
    next(error);
  }
};

export const getConversation = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const leadId = Array.isArray(req.params.leadId) ? req.params.leadId[0] : req.params.leadId;

    const messages = await messageService.getConversation(
      leadId,
      req.user?.role || 'SALES',
      req.user?.id || ''
    );

    res.json(messages);
  } catch (error) {
    next(error);
  }
};

export const getChats = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { phone } = req.query;

    const chats = await messageService.getChats(
      req.user?.role || 'SALES',
      req.user?.id || '',
      { phone: phone ? String(phone) : undefined }
    );

    res.json(chats);
  } catch (error) {
    next(error);
  }
};
