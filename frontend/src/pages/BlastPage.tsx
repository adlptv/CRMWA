import { useEffect, useState } from 'react';
import { leadApi, blastApi } from '../services';
import { Lead, BlastTask } from '../services/types';
import { Plus, CheckCircle, XCircle, Clock, Play } from 'lucide-react';
import { format } from 'date-fns';

export default function BlastPage() {
  const [leads, setLeads] = useState<Lead[]>([]);
  const [blasts, setBlasts] = useState<BlastTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);

  useEffect(() => {
    loadData();
    const interval = setInterval(loadData, 10000);
    return () => clearInterval(interval);
  }, []);

  const loadData = async () => {
    try {
      const [leadsData, blastsData] = await Promise.all([
        leadApi.getAll(),
        blastApi.getAll(),
      ]);
      setLeads(leadsData);
      setBlasts(blastsData);
    } catch (error) {
      console.error('Failed to load data:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleStartBlast = async (id: string) => {
    if (!confirm('Are you sure you want to start this blast?')) return;

    try {
      await blastApi.start(id);
      loadData();
    } catch (error) {
      console.error('Failed to start blast:', error);
      alert('Failed to start blast');
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'COMPLETED':
        return <CheckCircle className="w-4 h-4 text-green-500" />;
      case 'FAILED':
        return <XCircle className="w-4 h-4 text-red-500" />;
      case 'PROCESSING':
        return <Clock className="w-4 h-4 text-yellow-500 animate-spin" />;
      default:
        return <Clock className="w-4 h-4 text-gray-400" />;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'COMPLETED':
        return 'bg-green-100 text-green-800';
      case 'FAILED':
        return 'bg-red-100 text-red-800';
      case 'PROCESSING':
        return 'bg-yellow-100 text-yellow-800';
      default:
        return 'bg-gray-100 text-gray-800';
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
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-gray-900">WA Blast</h1>
        <button
          onClick={() => setShowModal(true)}
          className="btn btn-primary flex items-center gap-2"
        >
          <Plus className="w-4 h-4" />
          New Blast
        </button>
      </div>

      {/* Blast List */}
      <div className="card overflow-hidden">
        {blasts.length === 0 ? (
          <div className="text-center py-12 text-gray-500">
            No blast tasks yet. Create one to get started.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="text-left py-3 px-4 text-sm font-medium text-gray-500">Name</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-gray-500">Message</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-gray-500">Status</th>
                  <th className="text-center py-3 px-4 text-sm font-medium text-gray-500">Recipients</th>
                  <th className="text-center py-3 px-4 text-sm font-medium text-gray-500">Sent</th>
                  <th className="text-center py-3 px-4 text-sm font-medium text-gray-500">Failed</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-gray-500">Created</th>
                  <th className="text-right py-3 px-4 text-sm font-medium text-gray-500">Action</th>
                </tr>
              </thead>
              <tbody>
                {blasts.map((blast) => (
                  <tr key={blast.id} className="border-b border-gray-100 hover:bg-gray-50">
                    <td className="py-3 px-4 font-medium">{blast.name}</td>
                    <td className="py-3 px-4">
                      <p className="text-sm text-gray-600 truncate max-w-xs">
                        {blast.message}
                      </p>
                    </td>
                    <td className="py-3 px-4">
                      <span className={`badge ${getStatusColor(blast.status)} flex items-center gap-1 w-fit`}>
                        {getStatusIcon(blast.status)}
                        {blast.status}
                      </span>
                    </td>
                    <td className="py-3 px-4 text-center">{blast.totalRecipients}</td>
                    <td className="py-3 px-4 text-center text-green-600">{blast.sentCount}</td>
                    <td className="py-3 px-4 text-center text-red-600">{blast.failedCount}</td>
                    <td className="py-3 px-4 text-sm text-gray-500">
                      {format(new Date(blast.createdAt), 'MMM d, yyyy HH:mm')}
                    </td>
                    <td className="py-3 px-4 text-right">
                      {blast.status === 'PENDING' && (
                        <button
                          onClick={() => handleStartBlast(blast.id)}
                          className="btn btn-primary text-sm py-1"
                        >
                          <Play className="w-3 h-3 mr-1" />
                          Start
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Create Blast Modal */}
      {showModal && (
        <CreateBlastModal
          leads={leads}
          onClose={() => setShowModal(false)}
          onSuccess={() => {
            setShowModal(false);
            loadData();
          }}
        />
      )}
    </div>
  );
}

function CreateBlastModal({
  leads,
  onClose,
  onSuccess,
}: {
  leads: Lead[];
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [name, setName] = useState('');
  const [message, setMessage] = useState('');
  const [selectedLeads, setSelectedLeads] = useState<string[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [selectAll, setSelectAll] = useState(false);

  const handleSelectAll = () => {
    if (selectAll) {
      setSelectedLeads([]);
    } else {
      setSelectedLeads(leads.map((l) => l.id));
    }
    setSelectAll(!selectAll);
  };

  const handleLeadToggle = (leadId: string) => {
    setSelectedLeads((prev) =>
      prev.includes(leadId)
        ? prev.filter((id) => id !== leadId)
        : [...prev, leadId]
    );
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    if (selectedLeads.length === 0) {
      setError('Please select at least one lead');
      return;
    }

    setLoading(true);

    try {
      await blastApi.create({
        name,
        message,
        leadIds: selectedLeads,
      });
      onSuccess();
    } catch (err: any) {
      setError(err.response?.data?.error || 'Failed to create blast');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-xl max-w-2xl w-full max-h-[90vh] overflow-auto">
        <div className="p-6">
          <h2 className="text-xl font-bold mb-4">Create WA Blast</h2>

          {error && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg mb-4">
              {error}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="label">Blast Name</label>
              <input
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="input"
                placeholder="e.g., January Promo"
                required
              />
            </div>

            <div>
              <label className="label">Message</label>
              <textarea
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                className="input"
                rows={4}
                placeholder="Enter your message..."
                required
              />
            </div>

            <div>
              <div className="flex items-center justify-between mb-2">
                <label className="label mb-0">Select Leads ({selectedLeads.length} selected)</label>
                <button
                  type="button"
                  onClick={handleSelectAll}
                  className="text-sm text-primary-600 hover:text-primary-700"
                >
                  {selectAll ? 'Deselect All' : 'Select All'}
                </button>
              </div>
              <div className="border border-gray-200 rounded-lg max-h-60 overflow-auto">
                {leads.length === 0 ? (
                  <p className="p-4 text-gray-500 text-center">No leads available</p>
                ) : (
                  leads.map((lead) => (
                    <label
                      key={lead.id}
                      className="flex items-center gap-3 p-3 hover:bg-gray-50 cursor-pointer border-b border-gray-100 last:border-0"
                    >
                      <input
                        type="checkbox"
                        checked={selectedLeads.includes(lead.id)}
                        onChange={() => handleLeadToggle(lead.id)}
                        className="rounded border-gray-300 text-primary-600 focus:ring-primary-500"
                      />
                      <div className="flex-1">
                        <p className="font-medium">{lead.name}</p>
                        <p className="text-sm text-gray-500">{lead.phone}</p>
                      </div>
                      <span className={`badge badge-${lead.status.toLowerCase()}`}>
                        {lead.status.replace('_', ' ')}
                      </span>
                    </label>
                  ))
                )}
              </div>
            </div>

            <div className="flex gap-3 pt-2">
              <button
                type="button"
                onClick={onClose}
                className="btn btn-secondary flex-1"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={loading}
                className="btn btn-primary flex-1"
              >
                {loading ? 'Creating...' : 'Create Blast'}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
