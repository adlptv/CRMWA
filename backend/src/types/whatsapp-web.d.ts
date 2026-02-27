declare module 'whatsapp-web.js' {
  export interface ClientOptions {
    authStrategy?: any;
    puppeteer?: {
      headless?: boolean;
      args?: string[];
      executablePath?: string;
    };
  }

  export interface MessageId {
    id: string;
    fromMe: boolean;
    remote: string;
    _serialized?: string;
  }

  export interface Message {
    id: MessageId;
    from: string;
    to: string;
    body: string;
    fromMe: boolean;
    timestamp: number;
    type: string;
    hasMedia: boolean;
    author?: string;
    getChat(): Promise<Chat>;
    getContact(): Promise<Contact>;
  }

  export interface ChatId {
    user: string;
    server: string;
    _serialized: string;
  }

  export interface Chat {
    id: ChatId;
    name: string;
    isGroup: boolean;
    unreadCount: number;
    timestamp: number;
    lastMessage?: Message;
    getProfilePicUrl(): Promise<string>;
    fetchMessages(options?: { limit?: number }): Promise<Message[]>;
    sendSeen(): Promise<void>;
    clearMessages(): Promise<void>;
  }

  export interface Contact {
    id: { _serialized: string };
    name?: string;
    pushname?: string;
    number: string;
    isGroup: boolean;
    isWAContact: boolean;
    getProfilePicUrl(): Promise<string>;
  }

  export class Client {
    constructor(options?: ClientOptions);
    on(event: 'qr', listener: (qr: string) => void): this;
    on(event: 'ready', listener: () => void): this;
    on(event: 'message', listener: (message: Message) => void): this;
    on(event: 'auth_failure', listener: (msg: string) => void): this;
    on(event: 'disconnected', listener: (reason: string) => void): this;
    initialize(): Promise<void>;
    sendMessage(chatId: string, content: string): Promise<Message>;
    getChats(): Promise<Chat[]>;
    getChatById(chatId: string): Promise<Chat>;
    getContacts(): Promise<Contact[]>;
    destroy(): Promise<void>;
  }

  export class LocalAuth {
    constructor(options?: { dataPath?: string });
  }
}