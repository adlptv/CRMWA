import { body, query, validationResult } from 'express-validator';
import { NextFunction, Request, Response } from 'express';
import { leadService } from '../services/lead.service';
import { AppError } from '../middleware/error.middleware';
import { AuthRequest } from '../middleware/auth.middleware';
import { LeadSource, LeadStatus } from '@prisma/client';

export const createLeadValidation = [
  body('name').trim().notEmpty().withMessage('Name is required'),
  body('phone').trim().notEmpty().withMessage('Phone is required'),
  body('source').optional().isIn(['ORGANIC', 'IG', 'OTHER']).withMessage('Invalid source'),
  body('assignedTo').optional().isUUID().withMessage('Invalid user ID'),
];

export const updateLeadValidation = [
  body('name').optional().trim().notEmpty().withMessage('Name cannot be empty'),
  body('phone').optional().trim().notEmpty().withMessage('Phone cannot be empty'),
  body('source').optional().isIn(['ORGANIC', 'IG', 'OTHER']).withMessage('Invalid source'),
  body('status').optional().isIn(['NEW', 'FOLLOW_UP', 'DEAL', 'CANCEL']).withMessage('Invalid status'),
  body('assignedTo').optional({ checkFalsy: true }).isUUID().withMessage('Invalid user ID'),
];

export const createLead = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      throw new AppError(400, errors.array()[0].msg);
    }

    const { name, phone, source, notes, assignedTo } = req.body;
    const userId = req.user?.id;
    
    const lead = await leadService.create(
      {
        name,
        phone,
        source: source as LeadSource,
        notes,
        assignedTo,
      },
      userId
    );

    res.status(201).json(lead);
  } catch (error) {
    next(error);
  }
};

export const getLead = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const id = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const lead = await leadService.findById(id);

    if (req.user?.role !== 'ADMIN' && lead.assignedTo !== req.user?.id) {
      throw new AppError(403, 'Access denied');
    }

    res.json(lead);
  } catch (error) {
    next(error);
  }
};

export const getLeads = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { status, source, assignedTo, dateFrom, dateTo, search } = req.query;
    const userRole = req.user?.role || 'SALES';
    const userId = req.user?.id || '';

    const filters = {
      status: status ? String(status) as LeadStatus : undefined,
      source: source ? String(source) as LeadSource : undefined,
      assignedTo: assignedTo ? String(assignedTo) : undefined,
      dateFrom: dateFrom ? new Date(String(dateFrom)) : undefined,
      dateTo: dateTo ? new Date(String(dateTo)) : undefined,
      search: search ? String(search) : undefined,
    };

    const leads = await leadService.findAll(filters, userRole, userId);

    res.json(leads);
  } catch (error) {
    next(error);
  }
};

export const updateLead = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      throw new AppError(400, errors.array()[0].msg);
    }

    const id = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const { name, phone, source, status, notes, assignedTo } = req.body;
    const userId = req.user?.id;

    const existingLead = await leadService.findById(id);

    if (req.user?.role !== 'ADMIN' && existingLead.assignedTo !== req.user?.id) {
      throw new AppError(403, 'Access denied');
    }

    const lead = await leadService.update(
      id,
      {
        name,
        phone,
        source: source as LeadSource,
        status: status as LeadStatus,
        notes,
        assignedTo: assignedTo === '' ? null : assignedTo,
      },
      userId
    );

    res.json(lead);
  } catch (error) {
    next(error);
  }
};

export const deleteLead = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const id = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    
    if (req.user?.role !== 'ADMIN') {
      throw new AppError(403, 'Admin access required');
    }

    const result = await leadService.delete(id);
    res.json(result);
  } catch (error) {
    next(error);
  }
};

export const getLeadStats = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { dateFrom, dateTo } = req.query;
    const userRole = req.user?.role || 'SALES';
    const userId = req.user?.id || '';

    const stats = await leadService.getStats(
      userRole,
      userId,
      dateFrom ? new Date(String(dateFrom)) : undefined,
      dateTo ? new Date(String(dateTo)) : undefined
    );

    res.json(stats);
  } catch (error) {
    next(error);
  }
};
