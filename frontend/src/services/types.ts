export interface User {
  id: string;
  name: string;
  email: string;
  role: 'ADMIN' | 'SALES';
  isActive?: boolean;
  createdAt?: string;
}

export interface Lead {
  id: string;
  name: string;
  phone: string;
  source: 'ORGANIC' | 'IG' | 'OTHER';
  status: 'NEW' | 'FOLLOW_UP' | 'DEAL' | 'CANCEL';
  notes?: string;
  assignedTo?: string;
  assignedBy?: string;
  createdAt: string;
  updatedAt: string;
  assignedUser?: User;
  assignedByUser?: User;
  messages?: Message[];
}

export interface Message {
  id: string;
  leadId: string;
  phone: string;
  direction: 'INBOUND' | 'OUTBOUND';
  message: string;
  timestamp: string;
  handledBy?: string;
  handler?: User;
  lead?: Lead;
}

export interface BlastTask {
  id: string;
  name: string;
  message: string;
  status: 'PENDING' | 'PROCESSING' | 'COMPLETED' | 'FAILED';
  totalRecipients: number;
  sentCount: number;
  failedCount: number;
  createdBy: string;
  createdAt: string;
  completedAt?: string;
  creator?: User;
  logs?: BlastLog[];
}

export interface BlastLog {
  id: string;
  blastTaskId: string;
  leadId: string;
  phone: string;
  success: boolean;
  errorMessage?: string;
  sentAt: string;
  lead?: Lead;
}

export interface DashboardStats {
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

export interface SalesPerformance {
  id: string;
  name: string;
  totalLeads: number;
  dealCount: number;
  conversionRate: number;
}

export interface ChatItem {
  id: string;
  lead_id: string;
  phone: string;
  message: string;
  direction: 'INBOUND' | 'OUTBOUND';
  timestamp: string;
  lead_name: string;
  lead_status: string;
  assigned_to?: string;
}
