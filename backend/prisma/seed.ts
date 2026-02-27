import { PrismaClient, UserRole } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  console.log('Seeding database...');

  const adminPassword = await bcrypt.hash('admin123', 12);
  const sales1Password = await bcrypt.hash('sales123', 12);
  const sales2Password = await bcrypt.hash('sales123', 12);

  const admin = await prisma.user.upsert({
    where: { email: 'admin@crm.com' },
    update: {},
    create: {
      name: 'Admin User',
      email: 'admin@crm.com',
      password: adminPassword,
      role: 'ADMIN',
    },
  });

  const sales1 = await prisma.user.upsert({
    where: { email: 'sales1@crm.com' },
    update: {},
    create: {
      name: 'Sales One',
      email: 'sales1@crm.com',
      password: sales1Password,
      role: 'SALES',
    },
  });

  const sales2 = await prisma.user.upsert({
    where: { email: 'sales2@crm.com' },
    update: {},
    create: {
      name: 'Sales Two',
      email: 'sales2@crm.com',
      password: sales2Password,
      role: 'SALES',
    },
  });

  console.log('Users created:', { admin: admin.id, sales1: sales1.id, sales2: sales2.id });

  const leads = await Promise.all([
    prisma.lead.create({
      data: {
        name: 'John Doe',
        phone: '+6281234567890',
        source: 'ORGANIC',
        status: 'NEW',
        assignedTo: sales1.id,
        assignedBy: admin.id,
      },
    }),
    prisma.lead.create({
      data: {
        name: 'Jane Smith',
        phone: '+6281234567891',
        source: 'IG',
        status: 'FOLLOW_UP',
        assignedTo: sales1.id,
        assignedBy: admin.id,
        notes: 'Interested in premium package',
      },
    }),
    prisma.lead.create({
      data: {
        name: 'Bob Wilson',
        phone: '+6281234567892',
        source: 'OTHER',
        status: 'DEAL',
        assignedTo: sales2.id,
        assignedBy: admin.id,
        notes: 'Closed deal worth $5000',
      },
    }),
    prisma.lead.create({
      data: {
        name: 'Alice Brown',
        phone: '+6281234567893',
        source: 'IG',
        status: 'NEW',
        assignedTo: sales2.id,
        assignedBy: admin.id,
      },
    }),
    prisma.lead.create({
      data: {
        name: 'Charlie Davis',
        phone: '+6281234567894',
        source: 'ORGANIC',
        status: 'CANCEL',
        notes: 'Not interested anymore',
      },
    }),
  ]);

  console.log('Leads created:', leads.length);

  const messages = await Promise.all([
    prisma.message.create({
      data: {
        leadId: leads[0].id,
        phone: leads[0].phone,
        direction: 'INBOUND',
        message: 'Hi, I saw your product online. Can you tell me more?',
      },
    }),
    prisma.message.create({
      data: {
        leadId: leads[0].id,
        phone: leads[0].phone,
        direction: 'OUTBOUND',
        message: 'Hello! Thank you for your interest. Our product offers...',
        handledBy: sales1.id,
      },
    }),
    prisma.message.create({
      data: {
        leadId: leads[1].id,
        phone: leads[1].phone,
        direction: 'INBOUND',
        message: 'I saw your Instagram post. What are the prices?',
      },
    }),
    prisma.message.create({
      data: {
        leadId: leads[1].id,
        phone: leads[1].phone,
        direction: 'OUTBOUND',
        message: 'Hi! We have several packages starting from $99...',
        handledBy: sales1.id,
      },
    }),
    prisma.message.create({
      data: {
        leadId: leads[2].id,
        phone: leads[2].phone,
        direction: 'INBOUND',
        message: 'I want to place an order',
      },
    }),
    prisma.message.create({
      data: {
        leadId: leads[2].id,
        phone: leads[2].phone,
        direction: 'OUTBOUND',
        message: 'Great! Let me process your order right away.',
        handledBy: sales2.id,
      },
    }),
  ]);

  console.log('Messages created:', messages.length);

  console.log('Database seeded successfully!');
  console.log('\nDefault credentials:');
  console.log('Admin: admin@crm.com / admin123');
  console.log('Sales 1: sales1@crm.com / sales123');
  console.log('Sales 2: sales2@crm.com / sales123');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
