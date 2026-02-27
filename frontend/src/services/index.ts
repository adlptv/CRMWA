import api from './api';
import { User, Lead, Message, BlastTask, DashboardStats, ChatItem } from './types';

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

export interface WhatsAppMessage {
  id: string;
  body: string;
  fromMe: boolean;
  author?: string;
  timestamp: number;
  type: string;
  hasMedia: boolean;
  from: string;
  to: string;
}

export const authApi = {
  login: async (email: string, password: string) => {
    const response = await api.post<{ user: User; token: string }>('/auth/login', { email, password });
    return response.data;
  },

  getProfile: async () => {
    const response = await api.get<User>('/auth/profile');
    return response.data;
  },

  changePassword: async (currentPassword: string, newPassword: string) => {
    const response = await api.put('/auth/password', { currentPassword, newPassword });
    return response.data;
  },

  getUsers: async () => {
    const response = await api.get<User[]>('/auth/users');
    return response.data;
  },

  updateUser: async (id: string, data: { name?: string; isActive?: boolean }) => {
    const response = await api.put<User>(`/auth/users/${id}`, data);
    return response.data;
  },

  register: async (name: string, email: string, password: string, role: 'ADMIN' | 'SALES') => {
    const response = await api.post<User>('/auth/register', { name, email, password, role });
    return response.data;
  },
};

export const leadApi = {
  getAll: async (params?: {
    status?: string;
    source?: string;
    assignedTo?: string;
    dateFrom?: string;
    dateTo?: string;
    search?: string;
  }) => {
    const response = await api.get<Lead[]>('/leads', { params });
    return response.data;
  },

  getById: async (id: string) => {
    const response = await api.get<Lead>(`/leads/${id}`);
    return response.data;
  },

  create: async (data: {
    name: string;
    phone: string;
    source?: string;
    notes?: string;
    assignedTo?: string;
  }) => {
    const response = await api.post<Lead>('/leads', data);
    return response.data;
  },

  update: async (id: string, data: Partial<Lead>) => {
    const response = await api.put<Lead>(`/leads/${id}`, data);
    return response.data;
  },

  delete: async (id: string) => {
    const response = await api.delete(`/leads/${id}`);
    return response.data;
  },

  getStats: async (params?: { dateFrom?: string; dateTo?: string }) => {
    const response = await api.get('/leads/stats', { params });
    return response.data;
  },
};

export const messageApi = {
  send: async (leadId: string, message: string) => {
    const response = await api.post<Message>('/messages/send', { leadId, message });
    return response.data;
  },

  getConversation: async (leadId: string) => {
    const response = await api.get<Message[]>(`/messages/conversation/${leadId}`);
    return response.data;
  },

  getChats: async (phone?: string) => {
    const response = await api.get<ChatItem[]>('/messages/chats', { params: { phone } });
    return response.data;
  },
};

export const whatsappApi = {
  getStatus: async () => {
    const response = await api.get<{ connected: boolean; message: string }>('/whatsapp/status');
    return response.data;
  },

  getChats: async () => {
    const response = await api.get<WhatsAppChat[]>('/whatsapp/chats');
    return response.data;
  },

  getChatMessages: async (chatId: string, limit?: number) => {
    const response = await api.get<WhatsAppMessage[]>(`/whatsapp/chats/${encodeURIComponent(chatId)}/messages`, {
      params: { limit },
    });
    return response.data;
  },

  sendMessage: async (to: string, message: string, isGroup?: boolean) => {
    const response = await api.post<{ success: boolean; messageId?: string }>('/whatsapp/send', {
      to,
      message,
      isGroup,
    });
    return response.data;
  },
};

export const blastApi = {
  getAll: async () => {
    const response = await api.get<BlastTask[]>('/blast');
    return response.data;
  },

  getById: async (id: string) => {
    const response = await api.get<BlastTask>(`/blast/${id}`);
    return response.data;
  },

  create: async (data: { name: string; message: string; leadIds: string[] }) => {
    const response = await api.post<BlastTask>('/blast', data);
    return response.data;
  },

  start: async (id: string) => {
    const response = await api.post(`/blast/${id}/start`);
    return response.data;
  },
};

export const dashboardApi = {
  getStats: async (params?: { dateFrom?: string; dateTo?: string }) => {
    const response = await api.get<DashboardStats>('/dashboard', { params });
    return response.data;
  },

  getRecentLeads: async (limit?: number) => {
    const response = await api.get<Lead[]>('/dashboard/recent-leads', { params: { limit } });
    return response.data;
  },

  getRecentMessages: async (limit?: number) => {
    const response = await api.get<Message[]>('/dashboard/recent-messages', { params: { limit } });
    return response.data;
  },
};
