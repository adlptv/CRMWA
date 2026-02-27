const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function test() {
  try {
    await prisma.$connect();
    console.log('Database connected successfully!');
    await prisma.$disconnect();
  } catch (error) {
    console.error('Connection error:', error.message);
    process.exit(1);
  }
}

test();
