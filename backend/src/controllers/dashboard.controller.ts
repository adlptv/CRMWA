import { NextFunction, Request, Response } from 'express';
import { dashboardService } from '../services/dashboard.service';
import { AuthRequest } from '../middleware/auth.middleware';

export const getDashboard = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { dateFrom, dateTo } = req.query;

    let dashboard;

    if (req.user?.role === 'ADMIN') {
      dashboard = await dashboardService.getAdminDashboard(
        dateFrom ? new Date(dateFrom as string) : undefined,
        dateTo ? new Date(dateTo as string) : undefined
      );
    } else {
      dashboard = await dashboardService.getSalesDashboard(
        req.user?.id || '',
        dateFrom ? new Date(dateFrom as string) : undefined,
        dateTo ? new Date(dateTo as string) : undefined
      );
    }

    res.json(dashboard);
  } catch (error) {
    next(error);
  }
};

export const getRecentLeads = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { limit } = req.query;

    const leads = await dashboardService.getRecentLeads(
      req.user?.id || '',
      req.user?.role || 'SALES',
      limit ? parseInt(limit as string) : 10
    );

    res.json(leads);
  } catch (error) {
    next(error);
  }
};

export const getRecentMessages = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { limit } = req.query;

    const messages = await dashboardService.getRecentMessages(
      req.user?.id || '',
      req.user?.role || 'SALES',
      limit ? parseInt(limit as string) : 10
    );

    res.json(messages);
  } catch (error) {
    next(error);
  }
};
