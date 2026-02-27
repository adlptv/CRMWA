import { prisma } from '../config/database';

interface DashboardStats {
  leads: {
    total: number;
    new: number;
    followUp: number;
    deal: number;
    cancel: number;
  };
  messages: {
    total: number;
    inbound: number;
    outbound: number;
  };
  sales?: SalesPerformance[];
}

interface SalesPerformance {
  id: string;
  name: string;
  totalLeads: number;
  dealCount: number;
  conversionRate: number;
}

export class DashboardService {
  async getAdminDashboard(dateFrom?: Date, dateTo?: Date) {
    const dateFilter: any = {};
    if (dateFrom || dateTo) {
      dateFilter.createdAt = {};
      if (dateFrom) dateFilter.createdAt.gte = dateFrom;
      if (dateTo) dateFilter.createdAt.lte = dateTo;
    }

    const [totalLeads, newLeads, followUp, deal, cancel, totalMessages, inbound, outbound] = await Promise.all([
      prisma.lead.count({ where: dateFilter }),
      prisma.lead.count({ where: { ...dateFilter, status: 'NEW' } }),
      prisma.lead.count({ where: { ...dateFilter, status: 'FOLLOW_UP' } }),
      prisma.lead.count({ where: { ...dateFilter, status: 'DEAL' } }),
      prisma.lead.count({ where: { ...dateFilter, status: 'CANCEL' } }),
      prisma.message.count({ where: dateFilter }),
      prisma.message.count({ where: { ...dateFilter, direction: 'INBOUND' } }),
      prisma.message.count({ where: { ...dateFilter, direction: 'OUTBOUND' } }),
    ]);

    const salesUsers = await prisma.user.findMany({
      where: { role: 'SALES', isActive: true },
      select: { id: true, name: true },
    });

    const salesPerformance: SalesPerformance[] = await Promise.all(
      salesUsers.map(async (user) => {
        const userDateFilter = { ...dateFilter, assignedTo: user.id };
        
        const [userTotal, userDeals] = await Promise.all([
          prisma.lead.count({ where: userDateFilter }),
          prisma.lead.count({ where: { ...userDateFilter, status: 'DEAL' } }),
        ]);

        return {
          id: user.id,
          name: user.name,
          totalLeads: userTotal,
          dealCount: userDeals,
          conversionRate: userTotal > 0 ? Math.round((userDeals / userTotal) * 100) : 0,
        };
      })
    );

    return {
      leads: {
        total: totalLeads,
        new: newLeads,
        followUp,
        deal,
        cancel,
      },
      messages: {
        total: totalMessages,
        inbound,
        outbound,
      },
      sales: salesPerformance,
    };
  }

  async getSalesDashboard(userId: string, dateFrom?: Date, dateTo?: Date) {
    const dateFilter: any = { assignedTo: userId };
    if (dateFrom || dateTo) {
      dateFilter.createdAt = {};
      if (dateFrom) dateFilter.createdAt.gte = dateFrom;
      if (dateTo) dateFilter.createdAt.lte = dateTo;
    }

    const [totalLeads, newLeads, followUp, deal, cancel] = await Promise.all([
      prisma.lead.count({ where: dateFilter }),
      prisma.lead.count({ where: { ...dateFilter, status: 'NEW' } }),
      prisma.lead.count({ where: { ...dateFilter, status: 'FOLLOW_UP' } }),
      prisma.lead.count({ where: { ...dateFilter, status: 'DEAL' } }),
      prisma.lead.count({ where: { ...dateFilter, status: 'CANCEL' } }),
    ]);

    const leadIds = await prisma.lead.findMany({
      where: { assignedTo: userId },
      select: { id: true },
    });

    const leadIdList = leadIds.map((l) => l.id);

    const [totalMessages, inbound, outbound] = await Promise.all([
      prisma.message.count({ where: { leadId: { in: leadIdList } } }),
      prisma.message.count({ where: { leadId: { in: leadIdList }, direction: 'INBOUND' } }),
      prisma.message.count({ where: { leadId: { in: leadIdList }, direction: 'OUTBOUND' } }),
    ]);

    return {
      leads: {
        total: totalLeads,
        new: newLeads,
        followUp,
        deal,
        cancel,
      },
      messages: {
        total: totalMessages,
        inbound,
        outbound,
      },
    };
  }

  async getRecentLeads(userId: string, userRole: string, limit: number = 10) {
    const where: any = {};
    
    if (userRole !== 'ADMIN') {
      where.assignedTo = userId;
    }

    return prisma.lead.findMany({
      where,
      include: {
        assignedUser: { select: { id: true, name: true } },
      },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
  }

  async getRecentMessages(userId: string, userRole: string, limit: number = 10) {
    const where: any = {};

    if (userRole !== 'ADMIN') {
      where.lead = { assignedTo: userId };
    }

    return prisma.message.findMany({
      where,
      include: {
        lead: { select: { id: true, name: true, phone: true } },
        handler: { select: { id: true, name: true } },
      },
      orderBy: { timestamp: 'desc' },
      take: limit,
    });
  }
}

export const dashboardService = new DashboardService();
