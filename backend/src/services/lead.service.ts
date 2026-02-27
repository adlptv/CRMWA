import { prisma } from '../config/database';
import { LeadSource, LeadStatus } from '@prisma/client';
import { AppError } from '../middleware/error.middleware';

interface CreateLeadData {
  name: string;
  phone: string;
  source?: LeadSource;
  notes?: string;
  assignedTo?: string;
}

interface UpdateLeadData {
  name?: string;
  phone?: string;
  source?: LeadSource;
  status?: LeadStatus;
  notes?: string;
  assignedTo?: string | null;
}

interface LeadFilters {
  status?: LeadStatus;
  source?: LeadSource;
  assignedTo?: string;
  dateFrom?: Date;
  dateTo?: Date;
  search?: string;
}

export class LeadService {
  async create(data: CreateLeadData, createdBy?: string) {
    const existingLead = await prisma.lead.findUnique({
      where: { phone: data.phone },
    });

    if (existingLead) {
      throw new AppError(400, 'Lead with this phone number already exists');
    }

    const lead = await prisma.lead.create({
      data: {
        name: data.name,
        phone: data.phone,
        source: data.source || 'OTHER',
        status: 'NEW',
        notes: data.notes,
        assignedTo: data.assignedTo,
        assignedBy: data.assignedTo ? createdBy : null,
      },
      include: {
        assignedUser: {
          select: { id: true, name: true, email: true },
        },
      },
    });

    return lead;
  }

  async findById(id: string) {
    const lead = await prisma.lead.findUnique({
      where: { id },
      include: {
        assignedUser: {
          select: { id: true, name: true, email: true },
        },
        assignedByUser: {
          select: { id: true, name: true },
        },
        messages: {
          orderBy: { timestamp: 'desc' },
          take: 50,
        },
      },
    });

    if (!lead) {
      throw new AppError(404, 'Lead not found');
    }

    return lead;
  }

  async findByPhone(phone: string) {
    // Normalize phone number - remove non-digit characters
    const normalizedPhone = phone.replace(/\D/g, '');
    
    // Try exact match first
    let lead = await prisma.lead.findUnique({
      where: { phone: normalizedPhone },
    });

    if (lead) return lead;

    // Try with different formats
    const variations = [
      normalizedPhone,
      '+' + normalizedPhone,
      normalizedPhone.replace(/^62/, '0'), // Indonesian: 62xxx -> 0xxx
      '62' + normalizedPhone.replace(/^0/, ''), // Indonesian: 0xxx -> 62xxx
    ];

    for (const variation of variations) {
      lead = await prisma.lead.findFirst({
        where: { phone: variation },
      });
      if (lead) return lead;
    }

    // Try contains search as last resort
    if (normalizedPhone.length >= 8) {
      lead = await prisma.lead.findFirst({
        where: {
          phone: { contains: normalizedPhone.slice(-8) },
        },
      });
    }

    return lead;
  }

  async update(id: string, data: UpdateLeadData, updatedBy?: string) {
    const existingLead = await prisma.lead.findUnique({ where: { id } });
    
    if (!existingLead) {
      throw new AppError(404, 'Lead not found');
    }

    if (data.phone && data.phone !== existingLead.phone) {
      const phoneExists = await prisma.lead.findUnique({
        where: { phone: data.phone },
      });
      if (phoneExists) {
        throw new AppError(400, 'Phone number already in use');
      }
    }

    const updateData: any = { ...data };
    
    if (data.assignedTo !== undefined && data.assignedTo !== existingLead.assignedTo) {
      updateData.assignedBy = updatedBy;
    }

    const lead = await prisma.lead.update({
      where: { id },
      data: updateData,
      include: {
        assignedUser: {
          select: { id: true, name: true, email: true },
        },
      },
    });

    return lead;
  }

  async findAll(filters: LeadFilters, userRole: string, userId: string) {
    const where: any = {};

    if (userRole !== 'ADMIN') {
      where.assignedTo = userId;
    } else if (filters.assignedTo) {
      where.assignedTo = filters.assignedTo;
    }

    if (filters.status) {
      where.status = filters.status;
    }

    if (filters.source) {
      where.source = filters.source;
    }

    if (filters.dateFrom || filters.dateTo) {
      where.createdAt = {};
      if (filters.dateFrom) {
        where.createdAt.gte = filters.dateFrom;
      }
      if (filters.dateTo) {
        where.createdAt.lte = filters.dateTo;
      }
    }

    if (filters.search) {
      where.OR = [
        { name: { contains: filters.search, mode: 'insensitive' } },
        { phone: { contains: filters.search, mode: 'insensitive' } },
      ];
    }

    const leads = await prisma.lead.findMany({
      where,
      include: {
        assignedUser: {
          select: { id: true, name: true, email: true },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    return leads;
  }

  async delete(id: string) {
    const lead = await prisma.lead.findUnique({ where: { id } });
    
    if (!lead) {
      throw new AppError(404, 'Lead not found');
    }

    await prisma.lead.delete({ where: { id } });

    return { message: 'Lead deleted successfully' };
  }

  async getStats(userRole: string, userId: string, dateFrom?: Date, dateTo?: Date) {
    const where: any = {};

    if (userRole !== 'ADMIN') {
      where.assignedTo = userId;
    }

    if (dateFrom || dateTo) {
      where.createdAt = {};
      if (dateFrom) where.createdAt.gte = dateFrom;
      if (dateTo) where.createdAt.lte = dateTo;
    }

    const [total, newLeads, followUp, deal, cancel] = await Promise.all([
      prisma.lead.count({ where }),
      prisma.lead.count({ where: { ...where, status: 'NEW' } }),
      prisma.lead.count({ where: { ...where, status: 'FOLLOW_UP' } }),
      prisma.lead.count({ where: { ...where, status: 'DEAL' } }),
      prisma.lead.count({ where: { ...where, status: 'CANCEL' } }),
    ]);

    return {
      total,
      new: newLeads,
      followUp,
      deal,
      cancel,
    };
  }
}

export const leadService = new LeadService();
