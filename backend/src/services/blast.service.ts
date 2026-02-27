import { prisma } from '../config/database';
import { AppError } from '../middleware/error.middleware';
import { leadService } from './lead.service';
import { waGatewayService } from './wa-gateway.service';
import { config } from '../config';

interface CreateBlastData {
  name: string;
  message: string;
  leadIds: string[];
}

export class BlastService {
  private throttleMs: number;

  constructor() {
    this.throttleMs = config.messageThrottle.ms;
  }

  async createBlast(data: CreateBlastData, userId: string) {
    const leads = await prisma.lead.findMany({
      where: { id: { in: data.leadIds } },
      select: { id: true, phone: true, name: true },
    });

    if (leads.length === 0) {
      throw new AppError(400, 'No valid leads found');
    }

    const blastTask = await prisma.blastTask.create({
      data: {
        name: data.name,
        message: data.message,
        status: 'PENDING',
        totalRecipients: leads.length,
        createdBy: userId,
      },
    });

    return blastTask;
  }

  async processBlast(blastTaskId: string) {
    const blastTask = await prisma.blastTask.findUnique({
      where: { id: blastTaskId },
    });

    if (!blastTask) {
      throw new AppError(404, 'Blast task not found');
    }

    if (blastTask.status !== 'PENDING') {
      throw new AppError(400, 'Blast task already processed');
    }

    await prisma.blastTask.update({
      where: { id: blastTaskId },
      data: { status: 'PROCESSING' },
    });

    const logs = await prisma.blastLog.findMany({
      where: { blastTaskId },
      include: { lead: { select: { phone: true } } },
    });

    if (logs.length === 0) {
      const leads = await prisma.lead.findMany({
        select: { id: true, phone: true },
      });

      for (const lead of leads) {
        await prisma.blastLog.create({
          data: {
            blastTaskId,
            leadId: lead.id,
            phone: lead.phone,
            success: false,
          },
        });
      }
    }

    const allLogs = await prisma.blastLog.findMany({
      where: { blastTaskId, success: false },
    });

    let sentCount = 0;
    let failedCount = 0;

    for (const log of allLogs) {
      const result = await waGatewayService.sendMessage(log.phone, blastTask.message);

      if (result.success) {
        await prisma.blastLog.update({
          where: { id: log.id },
          data: { success: true },
        });
        sentCount++;

        await prisma.message.create({
          data: {
            leadId: log.leadId,
            phone: log.phone,
            direction: 'OUTBOUND',
            message: blastTask.message,
          },
        });
      } else {
        await prisma.blastLog.update({
          where: { id: log.id },
          data: { success: false, errorMessage: result.error },
        });
        failedCount++;
      }

      await this.sleep(this.throttleMs);
    }

    await prisma.blastTask.update({
      where: { id: blastTaskId },
      data: {
        status: 'COMPLETED',
        sentCount,
        failedCount,
        completedAt: new Date(),
      },
    });

    return { sentCount, failedCount };
  }

  async startBlast(blastTaskId: string) {
    this.processBlast(blastTaskId).catch((error) => {
      console.error('Blast processing error:', error);
      prisma.blastTask.update({
        where: { id: blastTaskId },
        data: { status: 'FAILED' },
      }).catch(console.error);
    });

    return { message: 'Blast started', blastTaskId };
  }

  async getAllBlasts() {
    return prisma.blastTask.findMany({
      include: {
        creator: { select: { id: true, name: true } },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async getBlastById(id: string) {
    const blast = await prisma.blastTask.findUnique({
      where: { id },
      include: {
        creator: { select: { id: true, name: true } },
        logs: {
          include: {
            lead: { select: { id: true, name: true, phone: true } },
          },
        },
      },
    });

    if (!blast) {
      throw new AppError(404, 'Blast task not found');
    }

    return blast;
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}

export const blastService = new BlastService();
