import { useEffect, useState } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { dashboardApi } from '../services';
import { DashboardStats, Lead, Message } from '../services/types';
import { Users, MessageSquare, TrendingUp, UserCheck, XCircle, Clock } from 'lucide-react';
import { format } from 'date-fns';

export default function DashboardPage() {
  const { user } = useAuth();
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [recentLeads, setRecentLeads] = useState<Lead[]>([]);
  const [recentMessages, setRecentMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(true);
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');

  const isAdmin = user?.role === 'ADMIN';

  useEffect(() => {
    loadData();
  }, [dateFrom, dateTo]);

  const loadData = async () => {
    setLoading(true);
    try {
      const params: any = {};
      if (dateFrom) params.dateFrom = dateFrom;
      if (dateTo) params.dateTo = dateTo;

      const [statsData, leadsData, messagesData] = await Promise.all([
        dashboardApi.getStats(params),
        dashboardApi.getRecentLeads(5),
        dashboardApi.getRecentMessages(5),
      ]);

      setStats(statsData);
      setRecentLeads(leadsData);
      setRecentMessages(messagesData);
    } catch (error) {
      console.error('Failed to load dashboard:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-600"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <h1 className="text-2xl font-bold text-gray-900">
          {isAdmin ? 'Admin Dashboard' : 'Sales Dashboard'}
        </h1>
        <div className="flex gap-2">
          <input
            type="date"
            value={dateFrom}
            onChange={(e) => setDateFrom(e.target.value)}
            className="input w-auto"
            placeholder="From"
          />
          <input
            type="date"
            value={dateTo}
            onChange={(e) => setDateTo(e.target.value)}
            className="input w-auto"
            placeholder="To"
          />
          {(dateFrom || dateTo) && (
            <button
              onClick={() => {
                setDateFrom('');
                setDateTo('');
              }}
              className="btn btn-secondary"
            >
              Clear
            </button>
          )}
        </div>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
        <div className="card p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-blue-100 rounded-lg">
              <Users className="w-5 h-5 text-blue-600" />
            </div>
            <div>
              <p className="text-sm text-gray-500">Total Leads</p>
              <p className="text-2xl font-bold">{stats?.leads.total || 0}</p>
            </div>
          </div>
        </div>

        <div className="card p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-yellow-100 rounded-lg">
              <Clock className="w-5 h-5 text-yellow-600" />
            </div>
            <div>
              <p className="text-sm text-gray-500">New</p>
              <p className="text-2xl font-bold">{stats?.leads.new || 0}</p>
            </div>
          </div>
        </div>

        <div className="card p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-orange-100 rounded-lg">
              <TrendingUp className="w-5 h-5 text-orange-600" />
            </div>
            <div>
              <p className="text-sm text-gray-500">Follow Up</p>
              <p className="text-2xl font-bold">{stats?.leads.followUp || 0}</p>
            </div>
          </div>
        </div>

        <div className="card p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-green-100 rounded-lg">
              <UserCheck className="w-5 h-5 text-green-600" />
            </div>
            <div>
              <p className="text-sm text-gray-500">Deal</p>
              <p className="text-2xl font-bold">{stats?.leads.deal || 0}</p>
            </div>
          </div>
        </div>

        <div className="card p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-red-100 rounded-lg">
              <XCircle className="w-5 h-5 text-red-600" />
            </div>
            <div>
              <p className="text-sm text-gray-500">Cancel</p>
              <p className="text-2xl font-bold">{stats?.leads.cancel || 0}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Message Stats */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="card p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-purple-100 rounded-lg">
              <MessageSquare className="w-5 h-5 text-purple-600" />
            </div>
            <div>
              <p className="text-sm text-gray-500">Total Messages</p>
              <p className="text-2xl font-bold">{stats?.messages.total || 0}</p>
            </div>
          </div>
        </div>

        <div className="card p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-indigo-100 rounded-lg">
              <MessageSquare className="w-5 h-5 text-indigo-600" />
            </div>
            <div>
              <p className="text-sm text-gray-500">Inbound</p>
              <p className="text-2xl font-bold">{stats?.messages.inbound || 0}</p>
            </div>
          </div>
        </div>

        <div className="card p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-teal-100 rounded-lg">
              <MessageSquare className="w-5 h-5 text-teal-600" />
            </div>
            <div>
              <p className="text-sm text-gray-500">Outbound</p>
              <p className="text-2xl font-bold">{stats?.messages.outbound || 0}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Sales Performance (Admin only) */}
      {isAdmin && stats?.sales && stats.sales.length > 0 && (
        <div className="card p-6">
          <h2 className="text-lg font-semibold mb-4">Sales Performance</h2>
          <div className="overflow-x-auto">
            <table className="min-w-full">
              <thead>
                <tr className="border-b border-gray-200">
                  <th className="text-left py-2 px-3 text-sm font-medium text-gray-500">Name</th>
                  <th className="text-right py-2 px-3 text-sm font-medium text-gray-500">Total Leads</th>
                  <th className="text-right py-2 px-3 text-sm font-medium text-gray-500">Deals</th>
                  <th className="text-right py-2 px-3 text-sm font-medium text-gray-500">Conversion</th>
                </tr>
              </thead>
              <tbody>
                {stats.sales.map((sales) => (
                  <tr key={sales.id} className="border-b border-gray-100">
                    <td className="py-2 px-3">{sales.name}</td>
                    <td className="py-2 px-3 text-right">{sales.totalLeads}</td>
                    <td className="py-2 px-3 text-right">{sales.dealCount}</td>
                    <td className="py-2 px-3 text-right">{sales.conversionRate}%</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Recent Activity */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="card p-6">
          <h2 className="text-lg font-semibold mb-4">Recent Leads</h2>
          <div className="space-y-3">
            {recentLeads.length === 0 ? (
              <p className="text-gray-500 text-sm">No recent leads</p>
            ) : (
              recentLeads.map((lead) => (
                <div key={lead.id} className="flex items-center justify-between py-2 border-b border-gray-100 last:border-0">
                  <div>
                    <p className="font-medium">{lead.name}</p>
                    <p className="text-sm text-gray-500">{lead.phone}</p>
                  </div>
                  <div className="text-right">
                    <span className={`badge badge-${lead.status.toLowerCase()}`}>
                      {lead.status.replace('_', ' ')}
                    </span>
                    <p className="text-xs text-gray-400 mt-1">
                      {format(new Date(lead.createdAt), 'MMM d, yyyy')}
                    </p>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>

        <div className="card p-6">
          <h2 className="text-lg font-semibold mb-4">Recent Messages</h2>
          <div className="space-y-3">
            {recentMessages.length === 0 ? (
              <p className="text-gray-500 text-sm">No recent messages</p>
            ) : (
              recentMessages.map((msg) => (
                <div key={msg.id} className="flex items-start justify-between py-2 border-b border-gray-100 last:border-0">
                  <div className="flex-1 min-w-0">
                    <p className="font-medium truncate">{msg.lead?.name || msg.phone}</p>
                    <p className="text-sm text-gray-500 truncate">{msg.message}</p>
                  </div>
                  <div className="text-right ml-2">
                    <span className={`badge ${msg.direction === 'INBOUND' ? 'bg-blue-100 text-blue-800' : 'bg-green-100 text-green-800'}`}>
                      {msg.direction.toLowerCase()}
                    </span>
                    <p className="text-xs text-gray-400 mt-1">
                      {format(new Date(msg.timestamp), 'MMM d, HH:mm')}
                    </p>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
