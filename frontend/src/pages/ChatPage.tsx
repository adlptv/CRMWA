import { useEffect, useState, useRef, useCallback } from 'react';
import { useParams } from 'react-router-dom';
import { whatsappApi, WhatsAppChat, WhatsAppMessage } from '../services';
import { Send, Search, RefreshCw, Users, User, MessageCircle } from 'lucide-react';
import { format } from 'date-fns';

type ChatFilter = 'all' | 'private' | 'groups';

export default function ChatPage() {
  const { leadId } = useParams();
  const [chats, setChats] = useState<WhatsAppChat[]>([]);
  const [selectedChat, setSelectedChat] = useState<WhatsAppChat | null>(null);
  const [messages, setMessages] = useState<WhatsAppMessage[]>([]);
  const [newMessage, setNewMessage] = useState('');
  const [loading, setLoading] = useState(true);
  const [loadingMessages, setLoadingMessages] = useState(false);
  const [sending, setSending] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [refreshing, setRefreshing] = useState(false);
  const [chatFilter, setChatFilter] = useState<ChatFilter>('all');
  const [connectionStatus, setConnectionStatus] = useState<{ connected: boolean; message: string } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const pollIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  const loadConnectionStatus = useCallback(async () => {
    try {
      const status = await whatsappApi.getStatus();
      setConnectionStatus(status);
      setError(null);
    } catch (error: any) {
      console.error('Failed to get connection status:', error);
      if (error?.code === 'ERR_NETWORK' || error?.message?.includes('Network Error')) {
        setConnectionStatus({ connected: false, message: 'Backend not reachable' });
      }
    }
  }, []);

  const loadChats = useCallback(async (showRefreshing = false) => {
    if (showRefreshing) setRefreshing(true);
    try {
      const chatsData = await whatsappApi.getChats();
      setChats(chatsData);
      setError(null);

      // If there's a leadId from URL, find and select that chat
      if (leadId && !selectedChat) {
        const chat = chatsData.find(c => c.phone === leadId || c.id.includes(leadId));
        if (chat) {
          setSelectedChat(chat);
        }
      }
    } catch (error: any) {
      console.error('Failed to load chats:', error);
      if (error?.code === 'ERR_NETWORK' || error?.message?.includes('Network Error')) {
        setError('Cannot connect to backend server. Make sure the backend is running on port 3000.');
      } else if (error?.response?.status === 500) {
        setError('WhatsApp is not connected. Please check the WhatsApp connection status on the backend.');
      }
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [leadId, selectedChat]);

  const loadMessages = useCallback(async (chatId: string) => {
    setLoadingMessages(true);
    try {
      const messagesData = await whatsappApi.getChatMessages(chatId, 100);
      setMessages(messagesData);
    } catch (error) {
      console.error('Failed to load messages:', error);
    } finally {
      setLoadingMessages(false);
    }
  }, []);

  // Initial load
  useEffect(() => {
    loadConnectionStatus();
    loadChats();
  }, [loadConnectionStatus, loadChats]);

  // Load messages when selected chat changes
  useEffect(() => {
    if (selectedChat) {
      loadMessages(selectedChat.id);
    }
  }, [selectedChat, loadMessages]);

  // Scroll to bottom when messages change
  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  // Polling for new chats and messages every 3 seconds for faster updates
  useEffect(() => {
    pollIntervalRef.current = setInterval(() => {
      loadChats(false);
      loadConnectionStatus();
      if (selectedChat) {
        loadMessages(selectedChat.id);
      }
    }, 3000);

    return () => {
      if (pollIntervalRef.current) {
        clearInterval(pollIntervalRef.current);
      }
    };
  }, [loadChats, loadMessages, loadConnectionStatus, selectedChat]);

  const handleSendMessage = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newMessage.trim() || !selectedChat) return;

    setSending(true);
    try {
      await whatsappApi.sendMessage(selectedChat.id, newMessage.trim(), selectedChat.isGroup);
      setNewMessage('');
      // Reload messages after sending
      await loadMessages(selectedChat.id);
      // Reload chats to update last message
      loadChats();
    } catch (error) {
      console.error('Failed to send message:', error);
      alert('Failed to send message');
    } finally {
      setSending(false);
    }
  };

  const handleRefresh = () => {
    loadConnectionStatus();
    loadChats(true);
    if (selectedChat) {
      loadMessages(selectedChat.id);
    }
  };

  const handleSelectChat = (chat: WhatsAppChat) => {
    setSelectedChat(chat);
  };

  // Filter chats based on search and filter
  const filteredChats = chats.filter((chat) => {
    // Apply type filter
    if (chatFilter === 'private' && chat.isGroup) return false;
    if (chatFilter === 'groups' && !chat.isGroup) return false;

    // Apply search filter
    if (!searchQuery) return true;
    const query = searchQuery.toLowerCase();
    return (
      chat.name.toLowerCase().includes(query) ||
      (chat.phone && chat.phone.includes(query))
    );
  });

  // Format timestamp - with validation to prevent "Invalid time value" crash
  const formatTime = (timestamp: number) => {
    try {
      if (!timestamp || isNaN(timestamp) || timestamp <= 0) {
        return '-';
      }
      const date = new Date(timestamp * 1000);
      // Check if date is valid
      if (isNaN(date.getTime())) {
        return '-';
      }
      const now = new Date();
      const isToday = date.toDateString() === now.toDateString();

      if (isToday) {
        return format(date, 'HH:mm');
      }
      return format(date, 'dd/MM HH:mm');
    } catch (error) {
      console.warn('Invalid timestamp:', timestamp, error);
      return '-';
    }
  };

  // Get last message preview
  const getLastMessagePreview = (chat: WhatsAppChat) => {
    if (!chat.lastMessage) return '';
    const body = chat.lastMessage.body;
    if (body.length > 30) {
      return body.substring(0, 30) + '...';
    }
    return body;
  };

  return (
    <div className="h-[calc(100vh-8rem)]">
      <div className="flex h-full gap-4">
        {/* Chat List */}
        <div className="w-80 flex-shrink-0 card flex flex-col">
          {/* Header */}
          <div className="p-4 border-b border-gray-200">
            <div className="flex items-center justify-between mb-3">
              <h1 className="text-lg font-semibold">WhatsApp Chats</h1>
              <button
                onClick={handleRefresh}
                disabled={refreshing}
                className="p-1 hover:bg-gray-100 rounded"
                title="Refresh"
              >
                <RefreshCw className={`w-4 h-4 text-gray-500 ${refreshing ? 'animate-spin' : ''}`} />
              </button>
            </div>

            {/* Connection Status */}
            {connectionStatus && (
              <div className={`text-xs px-2 py-1 rounded mb-2 ${connectionStatus.connected
                ? 'bg-green-100 text-green-700'
                : 'bg-red-100 text-red-700'
                }`}>
                {connectionStatus.connected ? '🟢 Connected' : '🔴 Disconnected'}
              </div>
            )}

            {/* Filter Tabs */}
            <div className="flex gap-1 mb-2">
              <button
                onClick={() => setChatFilter('all')}
                className={`flex-1 py-1 px-2 text-xs rounded ${chatFilter === 'all'
                  ? 'bg-primary-100 text-primary-700'
                  : 'bg-gray-100 text-gray-600'
                  }`}
              >
                <MessageCircle className="w-3 h-3 inline mr-1" />
                All
              </button>
              <button
                onClick={() => setChatFilter('private')}
                className={`flex-1 py-1 px-2 text-xs rounded ${chatFilter === 'private'
                  ? 'bg-primary-100 text-primary-700'
                  : 'bg-gray-100 text-gray-600'
                  }`}
              >
                <User className="w-3 h-3 inline mr-1" />
                Private
              </button>
              <button
                onClick={() => setChatFilter('groups')}
                className={`flex-1 py-1 px-2 text-xs rounded ${chatFilter === 'groups'
                  ? 'bg-primary-100 text-primary-700'
                  : 'bg-gray-100 text-gray-600'
                  }`}
              >
                <Users className="w-3 h-3 inline mr-1" />
                Groups
              </button>
            </div>

            {/* Search */}
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400" />
              <input
                type="text"
                placeholder="Search chats..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="input pl-9 text-sm"
              />
            </div>
          </div>

          {/* Chat List */}
          <div className="flex-1 overflow-auto">
            {loading ? (
              <div className="flex items-center justify-center h-32">
                <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-primary-600"></div>
              </div>
            ) : error ? (
              <div className="p-4">
                <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg text-sm mb-3">
                  <p className="font-medium mb-1">⚠️ Connection Error</p>
                  <p className="text-xs">{error}</p>
                </div>
                <button
                  onClick={handleRefresh}
                  className="btn btn-primary w-full text-sm"
                >
                  <RefreshCw className="w-4 h-4 inline mr-1" />
                  Retry
                </button>
              </div>
            ) : filteredChats.length === 0 ? (
              <p className="text-center text-gray-500 py-8 text-sm">No chats found</p>
            ) : (
              filteredChats.map((chat) => (
                <button
                  key={chat.id}
                  onClick={() => handleSelectChat(chat)}
                  className={`w-full text-left p-3 hover:bg-gray-50 border-b border-gray-100 ${selectedChat?.id === chat.id ? 'bg-primary-50' : ''
                    }`}
                >
                  <div className="flex items-start gap-3">
                    {/* Avatar */}
                    <div className={`w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0 ${chat.isGroup ? 'bg-blue-100 text-blue-600' : 'bg-green-100 text-green-600'
                      }`}>
                      {chat.isGroup ? (
                        <Users className="w-5 h-5" />
                      ) : (
                        <User className="w-5 h-5" />
                      )}
                    </div>

                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between">
                        <p className="font-medium truncate text-sm">{chat.name}</p>
                        <p className="text-xs text-gray-400">
                          {formatTime(chat.timestamp)}
                        </p>
                      </div>
                      <div className="flex items-center justify-between mt-1">
                        <p className="text-xs text-gray-500 truncate">
                          {chat.lastMessage?.fromMe && (
                            <span className="text-gray-400">✓ </span>
                          )}
                          {getLastMessagePreview(chat)}
                        </p>
                        {chat.unreadCount > 0 && (
                          <span className="bg-green-500 text-white text-xs px-1.5 py-0.5 rounded-full min-w-[20px] text-center">
                            {chat.unreadCount}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                </button>
              ))
            )}
          </div>
        </div>

        {/* Chat Window */}
        <div className="flex-1 card flex flex-col">
          {selectedChat ? (
            <>
              {/* Chat Header */}
              <div className="p-4 border-b border-gray-200">
                <div className="flex items-center gap-3">
                  <div className={`w-10 h-10 rounded-full flex items-center justify-center ${selectedChat.isGroup ? 'bg-blue-100 text-blue-600' : 'bg-green-100 text-green-600'
                    }`}>
                    {selectedChat.isGroup ? (
                      <Users className="w-5 h-5" />
                    ) : (
                      <User className="w-5 h-5" />
                    )}
                  </div>
                  <div className="flex-1">
                    <h2 className="font-semibold">{selectedChat.name}</h2>
                    <p className="text-sm text-gray-500">
                      {selectedChat.isGroup ? 'Group Chat' : selectedChat.phone || 'Private Chat'}
                    </p>
                  </div>
                  <span className={`text-xs px-2 py-1 rounded ${selectedChat.isGroup
                    ? 'bg-blue-100 text-blue-700'
                    : 'bg-green-100 text-green-700'
                    }`}>
                    {selectedChat.isGroup ? 'Group' : 'Private'}
                  </span>
                </div>
              </div>

              {/* Messages */}
              <div className="flex-1 overflow-auto p-4 space-y-3 bg-gray-50">
                {loadingMessages ? (
                  <div className="flex items-center justify-center h-32">
                    <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-primary-600"></div>
                  </div>
                ) : messages.length === 0 ? (
                  <p className="text-center text-gray-500 py-8">No messages</p>
                ) : (
                  messages.map((msg) => (
                    <div
                      key={msg.id}
                      className={`flex ${msg.fromMe ? 'justify-end' : 'justify-start'}`}
                    >
                      <div
                        className={`max-w-[70%] rounded-lg px-4 py-2 ${msg.fromMe
                          ? 'bg-primary-600 text-white'
                          : 'bg-white text-gray-900 shadow-sm'
                          }`}
                      >
                        {/* Show author name for group messages */}
                        {!msg.fromMe && selectedChat.isGroup && msg.author && (
                          <p className="text-xs text-blue-500 font-medium mb-1">
                            {msg.author}
                          </p>
                        )}
                        <p className="text-sm whitespace-pre-wrap">{msg.body}</p>
                        <p
                          className={`text-xs mt-1 ${msg.fromMe ? 'text-primary-200' : 'text-gray-500'
                            }`}
                        >
                          {formatTime(msg.timestamp)}
                        </p>
                      </div>
                    </div>
                  ))
                )}
                <div ref={messagesEndRef} />
              </div>

              {/* Message Input */}
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
            </>
          ) : (
            <div className="flex-1 flex flex-col items-center justify-center text-gray-500">
              <MessageCircle className="w-16 h-16 text-gray-300 mb-4" />
              <p className="text-lg font-medium">Select a chat</p>
              <p className="text-sm">Choose a conversation to start messaging</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}