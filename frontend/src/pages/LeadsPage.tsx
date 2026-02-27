import { useEffect, useState } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { leadApi } from '../services';
import { Lead, User } from '../services/types';
import { Plus, Search, Filter } from 'lucide-react';
import { format } from 'date-fns';
import { Link } from 'react-router-dom';
import { authApi } from '../services';

export default function LeadsPage() {
  const { user } = useAuth();
  const [leads, setLeads] = useState<Lead[]>([]);
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [editingLead, setEditingLead] = useState<Lead | null>(null);

  const [filters, setFilters] = useState({
    status: '',
    source: '',
    assignedTo: '',
    dateFrom: '',
    dateTo: '',
    search: '',
  });

  const isAdmin = user?.role === 'ADMIN';

  useEffect(() => {
    loadLeads();
    if (isAdmin) {
      loadUsers();
    }
  }, [filters]);

  const loadLeads = async () => {
    setLoading(true);
    try {
      const params: any = {};
      if (filters.status) params.status = filters.status;
      if (filters.source) params.source = filters.source;
      if (filters.assignedTo) params.assignedTo = filters.assignedTo;
      if (filters.dateFrom) params.dateFrom = filters.dateFrom;
      if (filters.dateTo) params.dateTo = filters.dateTo;
      if (filters.search) params.search = filters.search;

      const data = await leadApi.getAll(params);
      setLeads(data);
    } catch (error) {
      console.error('Failed to load leads:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadUsers = async () => {
    try {
      const data = await authApi.getUsers();
      setUsers(data);
    } catch (error) {
      console.error('Failed to load users:', error);
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Are you sure you want to delete this lead?')) return;

    try {
      await leadApi.delete(id);
      loadLeads();
    } catch (error) {
      console.error('Failed to delete lead:', error);
      alert('Failed to delete lead');
    }
  };

  const openEditModal = (lead: Lead) => {
    setEditingLead(lead);
    setShowModal(true);
  };

  const closeModal = () => {
    setShowModal(false);
    setEditingLead(null);
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <h1 className="text-2xl font-bold text-gray-900">Leads</h1>
        <button
          onClick={() => setShowModal(true)}
          className="btn btn-primary flex items-center gap-2"
        >
          <Plus className="w-4 h-4" />
          Add Lead
        </button>
      </div>

      {/* Filters */}
      <div className="card p-4">
        <div className="flex items-center gap-2 mb-3">
          <Filter className="w-4 h-4 text-gray-400" />
          <span className="text-sm font-medium text-gray-600">Filters</span>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-6 gap-3">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400" />
            <input
              type="text"
              placeholder="Search name/phone"
              value={filters.search}
              onChange={(e) => setFilters({ ...filters, search: e.target.value })}
              className="input pl-9"
            />
          </div>
          <select
            value={filters.status}
            onChange={(e) => setFilters({ ...filters, status: e.target.value })}
            className="input"
          >
            <option value="">All Status</option>
            <option value="NEW">New</option>
            <option value="FOLLOW_UP">Follow Up</option>
            <option value="DEAL">Deal</option>
            <option value="CANCEL">Cancel</option>
          </select>
          <select
            value={filters.source}
            onChange={(e) => setFilters({ ...filters, source: e.target.value })}
            className="input"
          >
            <option value="">All Source</option>
            <option value="ORGANIC">Organic</option>
            <option value="IG">Instagram</option>
            <option value="OTHER">Other</option>
          </select>
          {isAdmin && (
            <select
              value={filters.assignedTo}
              onChange={(e) => setFilters({ ...filters, assignedTo: e.target.value })}
              className="input"
            >
              <option value="">All Sales</option>
              {users.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.name}
                </option>
              ))}
            </select>
          )}
          <input
            type="date"
            value={filters.dateFrom}
            onChange={(e) => setFilters({ ...filters, dateFrom: e.target.value })}
            className="input"
            placeholder="From"
          />
          <input
            type="date"
            value={filters.dateTo}
            onChange={(e) => setFilters({ ...filters, dateTo: e.target.value })}
            className="input"
            placeholder="To"
          />
        </div>
      </div>

      {/* Leads Table */}
      <div className="card overflow-hidden">
        {loading ? (
          <div className="flex items-center justify-center h-64">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-600"></div>
          </div>
        ) : leads.length === 0 ? (
          <div className="text-center py-12 text-gray-500">
            No leads found
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="text-left py-3 px-4 text-sm font-medium text-gray-500">Name</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-gray-500">Phone</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-gray-500">Source</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-gray-500">Status</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-gray-500">Assigned To</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-gray-500">Created</th>
                  <th className="text-right py-3 px-4 text-sm font-medium text-gray-500">Actions</th>
                </tr>
              </thead>
              <tbody>
                {leads.map((lead) => (
                  <tr key={lead.id} className="border-b border-gray-100 hover:bg-gray-50">
                    <td className="py-3 px-4">
                      <Link to={`/leads/${lead.id}`} className="font-medium text-primary-600 hover:text-primary-700">
                        {lead.name}
                      </Link>
                    </td>
                    <td className="py-3 px-4 text-gray-600">{lead.phone}</td>
                    <td className="py-3 px-4">
                      <span className="badge bg-gray-100 text-gray-800">{lead.source}</span>
                    </td>
                    <td className="py-3 px-4">
                      <span className={`badge badge-${lead.status.toLowerCase()}`}>
                        {lead.status.replace('_', ' ')}
                      </span>
                    </td>
                    <td className="py-3 px-4 text-gray-600">
                      {lead.assignedUser?.name || '-'}
                    </td>
                    <td className="py-3 px-4 text-sm text-gray-500">
                      {format(new Date(lead.createdAt), 'MMM d, yyyy')}
                    </td>
                    <td className="py-3 px-4 text-right">
                      <button
                        onClick={() => openEditModal(lead)}
                        className="text-primary-600 hover:text-primary-700 text-sm font-medium mr-3"
                      >
                        Edit
                      </button>
                      {isAdmin && (
                        <button
                          onClick={() => handleDelete(lead.id)}
                          className="text-red-600 hover:text-red-700 text-sm font-medium"
                        >
                          Delete
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

      {/* Modal */}
      {showModal && (
        <LeadModal
          lead={editingLead}
          users={users}
          isAdmin={isAdmin}
          onClose={closeModal}
          onSuccess={() => {
            closeModal();
            loadLeads();
          }}
        />
      )}
    </div>
  );
}

function LeadModal({
  lead,
  users,
  isAdmin,
  onClose,
  onSuccess,
}: {
  lead: Lead | null;
  users: User[];
  isAdmin: boolean;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [formData, setFormData] = useState({
    name: lead?.name || '',
    phone: lead?.phone || '',
    source: lead?.source || 'OTHER',
    status: lead?.status || 'NEW',
    notes: lead?.notes || '',
    assignedTo: lead?.assignedTo || '',
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      if (lead) {
        await leadApi.update(lead.id, {
          ...formData,
          assignedTo: formData.assignedTo || undefined,
        });
      } else {
        await leadApi.create({
          ...formData,
          assignedTo: formData.assignedTo || undefined,
        });
      }
      onSuccess();
    } catch (err: any) {
      setError(err.response?.data?.error || 'Operation failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-xl max-w-md w-full max-h-[90vh] overflow-auto">
        <div className="p-6">
          <h2 className="text-xl font-bold mb-4">
            {lead ? 'Edit Lead' : 'Add Lead'}
          </h2>

          {error && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg mb-4">
              {error}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="label">Name</label>
              <input
                type="text"
                value={formData.name}
                onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                className="input"
                required
              />
            </div>

            <div>
              <label className="label">Phone</label>
              <input
                type="text"
                value={formData.phone}
                onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
                className="input"
                required
              />
            </div>

            <div>
              <label className="label">Source</label>
              <select
                value={formData.source}
                onChange={(e) => setFormData({ ...formData, source: e.target.value as 'ORGANIC' | 'IG' | 'OTHER' })}
                className="input"
              >
                <option value="ORGANIC">Organic</option>
                <option value="IG">Instagram</option>
                <option value="OTHER">Other</option>
              </select>
            </div>

            {lead && (
              <div>
                <label className="label">Status</label>
                <select
                  value={formData.status}
                  onChange={(e) => setFormData({ ...formData, status: e.target.value as any })}
                  className="input"
                >
                  <option value="NEW">New</option>
                  <option value="FOLLOW_UP">Follow Up</option>
                  <option value="DEAL">Deal</option>
                  <option value="CANCEL">Cancel</option>
                </select>
              </div>
            )}

            {isAdmin && (
              <div>
                <label className="label">Assign To</label>
                <select
                  value={formData.assignedTo}
                  onChange={(e) => setFormData({ ...formData, assignedTo: e.target.value })}
                  className="input"
                >
                  <option value="">Unassigned</option>
                  {users
                    .filter((u) => u.role === 'SALES' && u.isActive !== false)
                    .map((u) => (
                      <option key={u.id} value={u.id}>
                        {u.name}
                      </option>
                    ))}
                </select>
              </div>
            )}

            <div>
              <label className="label">Notes</label>
              <textarea
                value={formData.notes}
                onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
                className="input"
                rows={3}
              />
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
                {loading ? 'Saving...' : 'Save'}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
