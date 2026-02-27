import { Client, LocalAuth, Message } from 'whatsapp-web.js';
import * as qrcode from 'qrcode-terminal';
import { messageService } from './message.service';

export interface WhatsAppChat {
  id: string;
  name: string;
  phone?: string;
  isGroup: boolean;
  unreadCount: number;
  timestamp: number;
  lastMessage?: {
    body: string;
    fromMe: boolean;
    timestamp: number;
  };
  profilePic?: string;
}

export interface WhatsAppContact {
  id: string;
  name: string;
  phone: string;
  pushname?: string;
  isGroup: boolean;
  isWAContact: boolean;
  profilePic?: string;
}

class WhatsAppWebService {
  private client: Client | null = null;
  private isReady: boolean = false;
  private onMessageCallback: ((phone: string, message: string, name?: string) => Promise<void>) | null = null;

  async initialize(): Promise<void> {
    if (this.client) {
      console.log('WhatsApp client already initialized');
      return;
    }

    console.log('Initializing WhatsApp Web client...');

    this.client = new Client({
      authStrategy: new LocalAuth({
        dataPath: './.wwebjs_auth',
      }),
      puppeteer: {
        headless: false,
        executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
        args: [
          '--no-sandbox',
          '--disable-setuid-sandbox',
          '--disable-dev-shm-usage',
          '--disable-accelerated-2d-canvas',
          '--no-first-run',
          '--no-zygote',
          '--disable-gpu',
        ],
      },
    });

    // QR Code event
    this.client.on('qr', (qr: string) => {
      console.log('\n========================================');
      console.log('Scan QR Code berikut dengan WhatsApp Anda:');
      console.log('========================================\n');
      qrcode.generate(qr, { small: true });
      console.log('\n========================================');
    });

    // Ready event
    this.client.on('ready', () => {
      console.log('✅ WhatsApp Client is ready!');
      this.isReady = true;
    });

    // Message received event
    this.client.on('message', async (message: Message) => {
      try {
        // Skip messages from self or status broadcasts
        if (message.fromMe || message.from.includes('status@broadcast')) {
          return;
        }

        // Get chat info
        const chat = await message.getChat();
        const contact = await message.getContact();
        
        // Determine if it's a group
        const isGroup = message.from.includes('@g.us');
        
        // Get phone number - handle different ID formats (@c.us, @lid, etc.)
        let phone = message.from;
        if (message.from.includes('@')) {
          phone = message.from.split('@')[0];
        }
        
        const messageBody = message.body;
        const chatName = chat.name || contact.pushname || contact.name || phone;

        console.log(`📥 Incoming message from ${phone} (${chatName}): ${messageBody}`);
        console.log(`   Chat ID: ${message.from}, Is Group: ${isGroup}`);

        // Save all incoming messages to database for tracking
        if (!isGroup) {
          try {
            await messageService.handleIncomingMessage(phone, messageBody, chatName);
            console.log(`   ✅ Message saved to database`);
          } catch (error) {
            console.error(`   ❌ Failed to save message:`, error);
          }
        }
      } catch (error) {
        console.error('Error handling incoming message:', error);
      }
    });

    // Auth failure event
    this.client.on('auth_failure', (msg: string) => {
      console.error('❌ Authentication failed:', msg);
      this.isReady = false;
    });

    // Disconnected event
    this.client.on('disconnected', (reason: string) => {
      console.log('⚠️ WhatsApp client disconnected:', reason);
      this.isReady = false;
    });

    // Initialize the client
    await this.client.initialize();
  }

  async getAllChats(): Promise<WhatsAppChat[]> {
    if (!this.client || !this.isReady) {
      throw new Error('WhatsApp client not ready');
    }

    const chats = await this.client.getChats();
    const chatList: WhatsAppChat[] = [];

    for (const chat of chats) {
      // Skip status broadcasts and other non-standard chats
      if (chat.id._serialized.includes('status@broadcast')) {
        continue;
      }

      let profilePic: string | undefined;
      try {
        profilePic = await chat.getProfilePicUrl();
      } catch {
        // Profile pic not available
      }

      const isGroup = chat.isGroup;
      const phone = isGroup ? undefined : chat.id.user;

      chatList.push({
        id: chat.id._serialized,
        name: chat.name || chat.id.user || 'Unknown',
        phone,
        isGroup,
        unreadCount: chat.unreadCount,
        timestamp: chat.timestamp,
        lastMessage: chat.lastMessage ? {
          body: chat.lastMessage.body,
          fromMe: chat.lastMessage.fromMe,
          timestamp: chat.lastMessage.timestamp,
        } : undefined,
        profilePic,
      });
    }

    // Sort by timestamp (most recent first)
    return chatList.sort((a, b) => b.timestamp - a.timestamp);
  }

  async getContacts(): Promise<WhatsAppContact[]> {
    if (!this.client || !this.isReady) {
      throw new Error('WhatsApp client not ready');
    }

    const contacts = await this.client.getContacts();
    const contactList: WhatsAppContact[] = [];

    for (const contact of contacts) {
      // Skip blocked, not in WhatsApp, and groups (will be handled separately)
      if (contact.isGroup || !contact.isWAContact) {
        continue;
      }

      let profilePic: string | undefined;
      try {
        profilePic = await contact.getProfilePicUrl();
      } catch {
        // Profile pic not available
      }

      contactList.push({
        id: contact.id._serialized,
        name: contact.name || contact.pushname || contact.number || 'Unknown',
        phone: contact.number,
        pushname: contact.pushname,
        isGroup: contact.isGroup,
        isWAContact: contact.isWAContact,
        profilePic,
      });
    }

    // Sort alphabetically by name
    return contactList.sort((a, b) => a.name.localeCompare(b.name));
  }

  async getChatMessages(chatId: string, limit: number = 50): Promise<any[]> {
    if (!this.client || !this.isReady) {
      throw new Error('WhatsApp client not ready');
    }

    const chat = await this.client.getChatById(chatId);
    const messages = await chat.fetchMessages({ limit });

    return messages.map((msg) => ({
      id: msg.id.id,
      body: msg.body,
      fromMe: msg.fromMe,
      author: msg.author,
      timestamp: msg.timestamp,
      type: msg.type,
      hasMedia: msg.hasMedia,
      from: msg.from,
      to: msg.to,
    }));
  }

  async sendMessage(to: string, message: string): Promise<{ success: boolean; messageId?: string; error?: string }> {
    if (!this.client || !this.isReady) {
      return { success: false, error: 'WhatsApp client not ready. Please scan QR code first.' };
    }

    try {
      // Format chat ID
      let chatId = to;
      if (!chatId.includes('@')) {
        // Determine if it's a group or private chat
        chatId = `${to}@c.us`;
      }

      const sentMessage = await this.client.sendMessage(chatId, message);
      console.log(`✅ Message sent to ${to}: ${message}`);
      
      return { success: true, messageId: sentMessage.id.id };
    } catch (error) {
      const errorMsg = (error as Error).message;
      console.error(`❌ Failed to send message to ${to}:`, errorMsg);
      return { success: false, error: errorMsg };
    }
  }

  async sendGroupMessage(groupId: string, message: string): Promise<{ success: boolean; messageId?: string; error?: string }> {
    if (!this.client || !this.isReady) {
      return { success: false, error: 'WhatsApp client not ready. Please scan QR code first.' };
    }

    try {
      let chatId = groupId;
      if (!chatId.includes('@')) {
        chatId = `${groupId}@g.us`;
      }

      const sentMessage = await this.client.sendMessage(chatId, message);
      console.log(`✅ Group message sent to ${groupId}: ${message}`);
      
      return { success: true, messageId: sentMessage.id.id };
    } catch (error) {
      const errorMsg = (error as Error).message;
      console.error(`❌ Failed to send group message to ${groupId}:`, errorMsg);
      return { success: false, error: errorMsg };
    }
  }

  isConnected(): boolean {
    return this.isReady;
  }

  getStatus(): { connected: boolean; message: string } {
    if (this.isReady) {
      return { connected: true, message: 'WhatsApp client is connected and ready' };
    }
    return { connected: false, message: 'WhatsApp client is not connected. Please scan QR code.' };
  }

  onMessage(callback: (phone: string, message: string, name?: string) => Promise<void>): void {
    this.onMessageCallback = callback;
  }

  async destroy(): Promise<void> {
    if (this.client) {
      await this.client.destroy();
      this.client = null;
      this.isReady = false;
      console.log('WhatsApp client destroyed');
    }
  }
}

export const whatsAppWebService = new WhatsAppWebService();
