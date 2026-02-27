import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { leadApi, messageApi } from '../services';
import { Lead, Message } from '../services/types';
import { ArrowLeft, Send } from 'lucide-react';
import { format } from 'date-fns';

export default function LeadDetailPage() {
  const { id } = useParams();
  const [lead, setLead] = useState<Lead | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(true);
  const [newMessage, setNewMessage] = useState('');
  const [sending, setSending] = useState(false);

  useEffect(() => {
    loadData();
  }, [id]);

  const loadData = async () => {
    if (!id) return;
    setLoading(true);
    try {
      const leadData = await leadApi.getById(id);
      setLead(leadData);
      setMessages(leadData.messages || []);
    } catch (error) {
      console.error('Failed to load lead:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleSendMessage = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newMessage.trim() || !lead) return;

    setSending(true);
    try {
      const sentMessage = await messageApi.send(lead.id, newMessage.trim());
      setMessages([...messages, sentMessage]);
      setNewMessage('');
    } catch (error) {
      console.error('Failed to send message:', error);
      alert('Failed to send message');
    } finally {
      setSending(false);
    }
  };

  const handleStatusChange = async (status: string) => {
    if (!lead) return;
    try {
      const updated = await leadApi.update(lead.id, { status: status as any });
      setLead(updated);
    } catch (error) {
      console.error('Failed to update status:', error);
      alert('Failed to update status');
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-600"></div>
      </div>
    );
  }

  if (!lead) {
    return (
      <div className="text-center py-12">
        <p className="text-gray-500">Lead not found</p>
        <Link to="/leads" className="text-primary-600 hover:underline mt-2 inline-block">
          Back to leads
        </Link>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <Link to="/leads" className="p-2 hover:bg-gray-100 rounded-lg">
          <ArrowLeft className="w-5 h-5" />
        </Link>
        <div className="flex-1">
          <h1 className="text-2xl font-bold text-gray-900">{lead.name}</h1>
          <p className="text-gray-500">{lead.phone}</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Lead Info */}
        <div className="lg:col-span-1 space-y-4">
          <div className="card p-4">
            <h2 className="font-semibold mb-3">Lead Information</h2>
            <div className="space-y-3">
              <div>
                <p className="text-sm text-gray-500">Source</p>
                <span className="badge bg-gray-100 text-gray-800">{lead.source}</span>
              </div>
              <div>
                <p className="text-sm text-gray-500">Status</p>
                <select
                  value={lead.status}
                  onChange={(e) => handleStatusChange(e.target.value)}
                  className="input mt-1"
                >
                  <option value="NEW">New</option>
                  <option value="FOLLOW_UP">Follow Up</option>
                  <option value="DEAL">Deal</option>
                  <option value="CANCEL">Cancel</option>
                </select>
              </div>
              <div>
                <p className="text-sm text-gray-500">Assigned To</p>
                <p className="font-medium">{lead.assignedUser?.name || 'Unassigned'}</p>
              </div>
              <div>
                <p className="text-sm text-gray-500">Created</p>
                <p className="font-medium">
                  {format(new Date(lead.createdAt), 'MMM d, yyyy HH:mm')}
                </p>
              </div>
              {lead.notes && (
                <div>
                  <p className="text-sm text-gray-500">Notes</p>
                  <p className="text-gray-700">{lead.notes}</p>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Chat */}
        <div className="lg:col-span-2">
          <div className="card flex flex-col h-[600px]">
            <div className="p-4 border-b border-gray-200">
              <h2 className="font-semibold">Messages</h2>
            </div>

            <div className="flex-1 overflow-auto p-4 space-y-3">
              {messages.length === 0 ? (
                <p className="text-center text-gray-500 py-8">No messages yet</p>
              ) : (
                messages.map((msg) => (
                  <div
                    key={msg.id}
                    className={`flex ${msg.direction === 'OUTBOUND' ? 'justify-end' : 'justify-start'}`}
                  >
                    <div
                      className={`max-w-[70%] rounded-lg px-4 py-2 ${
                        msg.direction === 'OUTBOUND'
                          ? 'bg-primary-600 text-white'
                          : 'bg-gray-100 text-gray-900'
                      }`}
                    >
                      <p className="text-sm">{msg.message}</p>
                      <p
                        className={`text-xs mt-1 ${
                          msg.direction === 'OUTBOUND' ? 'text-primary-200' : 'text-gray-500'
                        }`}
                      >
                        {format(new Date(msg.timestamp), 'MMM d, HH:mm')}
                        {msg.handler && ` • ${msg.handler.name}`}
                      </p>
                    </div>
                  </div>
                ))
              )}
            </div>

            <form onSubmit={handleSendMessage} className="p-4 border-t border-gray-200">
              <div className="flex gap-2">
                <input
                  type="text"
                  value={newMessage}
                  onChange={(e) => setNewMessage(e.target.value)}
                  placeholder="Type a message..."
                  className="input flex-1"
                />
                <button
                  type="submit"
                  disabled={sending || !newMessage.trim()}
                  className="btn btn-primary disabled:opacity-50"
                >
                  <Send className="w-4 h-4" />
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
}
