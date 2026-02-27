import { prisma } from '../config/database';
import { MessageDirection } from '@prisma/client';
import { AppError } from '../middleware/error.middleware';
import { leadService } from './lead.service';
import { waGatewayService } from './wa-gateway.service';

interface CreateMessageData {
  leadId?: string;
  phone: string;
  direction: MessageDirection;
  message: string;
  handledBy?: string;
}

interface MessageFilters {
  leadId?: string;
  phone?: string;
  direction?: MessageDirection;
  dateFrom?: Date;
  dateTo?: Date;
}

export class MessageService {
  async create(data: CreateMessageData) {
    let leadId = data.leadId;
    let lead = null;

    if (!leadId) {
      lead = await leadService.findByPhone(data.phone);
      if (!lead) {
        lead = await leadService.create({
          name: `Lead ${data.phone}`,
          phone: data.phone,
          source: 'OTHER',
        });
      }
      leadId = lead.id;
    }

    const message = await prisma.message.create({
      data: {
        leadId,
        phone: data.phone,
        direction: data.direction,
        message: data.message,
        handledBy: data.handledBy,
      },
      include: {
        lead: {
          select: { id: true, name: true, phone: true, status: true },
        },
      },
    });

    return message;
  }

  async handleIncomingMessage(phone: string, message: string, contactName?: string) {
    // Normalize phone number - remove any non-digit characters except +
    let normalizedPhone = phone.replace(/\D/g, '');
    // Ensure it starts with country code (add 0 handling for Indonesian numbers)
    if (normalizedPhone.startsWith('0')) {
      normalizedPhone = '62' + normalizedPhone.substring(1);
    }

    let lead = await leadService.findByPhone(normalizedPhone);

    if (!lead) {
      // Also try with + prefix
      lead = await leadService.findByPhone('+' + normalizedPhone);
    }

    if (!lead) {
      // Also try without leading zeros
      lead = await leadService.findByPhone(normalizedPhone.replace(/^0+/, ''));
    }

    if (!lead) {
      lead = await leadService.create({
        name: contactName || `Lead ${normalizedPhone}`,
        phone: normalizedPhone,
        source: 'OTHER',
      });
    } else if (contactName && lead.name.startsWith('Lead ')) {
      // Update lead name if we have a real name from WhatsApp
      await prisma.lead.update({
        where: { id: lead.id },
        data: { name: contactName },
      });
    }

    const savedMessage = await prisma.message.create({
      data: {
        leadId: lead.id,
        phone: normalizedPhone,
        direction: 'INBOUND',
        message,
      },
      include: {
        lead: true,
      },
    });

    return savedMessage;
  }

  async sendMessage(leadId: string, message: string, userId: string) {
    const lead = await leadService.findById(leadId);

    if (!lead) {
      throw new AppError(404, 'Lead not found');
    }

    const sent = await waGatewayService.sendMessage(lead.phone, message);

    if (!sent.success) {
      throw new AppError(500, sent.error || 'Failed to send message');
    }

    const savedMessage = await prisma.message.create({
      data: {
        leadId,
        phone: lead.phone,
        direction: 'OUTBOUND',
        message,
        handledBy: userId,
      },
      include: {
        lead: {
          select: { id: true, name: true, phone: true },
        },
      },
    });

    return savedMessage;
  }

  async getConversation(leadId: string, userRole: string, userId: string) {
    const lead = await leadService.findById(leadId);

    if (!lead) {
      throw new AppError(404, 'Lead not found');
    }

    if (userRole !== 'ADMIN' && lead.assignedTo !== userId) {
      throw new AppError(403, 'Access denied');
    }

    const messages = await prisma.message.findMany({
      where: { leadId },
      orderBy: { timestamp: 'asc' },
      include: {
        handler: {
          select: { id: true, name: true },
        },
      },
    });

    return messages;
  }

  async getChats(userRole: string, userId: string, filters?: MessageFilters) {
    // Get all leads with their latest message
    const leads = await prisma.lead.findMany({
      where: userRole !== 'ADMIN' ? { assignedTo: userId } : undefined,
      include: {
        messages: {
          orderBy: { timestamp: 'desc' },
          take: 1,
        },
      },
    });

    // Filter by phone if provided
    const filteredLeads = filters?.phone
      ? leads.filter((lead) => lead.phone.includes(filters.phone!))
      : leads;

    // Transform to chat list format
    const chats = filteredLeads
      .filter((lead) => lead.messages.length > 0)
      .map((lead) => ({
        id: lead.messages[0].id,
        lead_id: lead.id,
        lead_name: lead.name,
        lead_status: lead.status,
        phone: lead.phone,
        message: lead.messages[0].message,
        direction: lead.messages[0].direction,
        timestamp: lead.messages[0].timestamp,
        assigned_to: lead.assignedTo,
      }))
      .sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());

    return chats;
  }

  async getMessagesByLead(leadId: string) {
    return prisma.message.findMany({
      where: { leadId },
      orderBy: { timestamp: 'asc' },
    });
  }
}

export const messageService = new MessageService();
