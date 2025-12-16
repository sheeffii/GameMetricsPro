import { useEffect, useState } from 'react';
import axios from 'axios';
import { LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import io from 'socket.io-client';

export default function Dashboard() {
  const [stats, setStats] = useState({
    totalEvents: 0,
    totalPlayers: 0,
    eventsPerSecond: 0,
    errorRate: 0,
  });
  const [eventHistory, setEventHistory] = useState<any[]>([]);
  const [kafkaHealth, setKafkaHealth] = useState<any>({});

  useEffect(() => {
    // Fetch initial stats
    const fetchStats = async () => {
      try {
        const response = await axios.get('/api/stats');
        setStats(response.data);
      } catch (error) {
        console.error('Error fetching stats:', error);
      }
    };

    fetchStats();
    const interval = setInterval(fetchStats, 5000);

    // WebSocket for real-time updates
    const socket = io(process.env.NEXT_PUBLIC_WS_URL || 'ws://localhost:8080/ws');
    socket.on('event', (data: any) => {
      setEventHistory((prev) => [...prev.slice(-99), data].slice(-100));
    });

    return () => {
      clearInterval(interval);
      socket.close();
    };
  }, []);

  return (
    <div style={{ padding: '20px' }}>
      <h1>GameMetrics Pro - Admin Dashboard</h1>
      
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '20px', marginBottom: '30px' }}>
        <div style={{ padding: '20px', background: '#f0f0f0', borderRadius: '8px' }}>
          <h3>Total Events</h3>
          <p style={{ fontSize: '24px', fontWeight: 'bold' }}>{stats.totalEvents.toLocaleString()}</p>
        </div>
        <div style={{ padding: '20px', background: '#f0f0f0', borderRadius: '8px' }}>
          <h3>Total Players</h3>
          <p style={{ fontSize: '24px', fontWeight: 'bold' }}>{stats.totalPlayers.toLocaleString()}</p>
        </div>
        <div style={{ padding: '20px', background: '#f0f0f0', borderRadius: '8px' }}>
          <h3>Events/sec</h3>
          <p style={{ fontSize: '24px', fontWeight: 'bold' }}>{stats.eventsPerSecond.toFixed(2)}</p>
        </div>
        <div style={{ padding: '20px', background: '#f0f0f0', borderRadius: '8px' }}>
          <h3>Error Rate</h3>
          <p style={{ fontSize: '24px', fontWeight: 'bold' }}>{(stats.errorRate * 100).toFixed(2)}%</p>
        </div>
      </div>

      <div style={{ marginBottom: '30px' }}>
        <h2>Event Rate Over Time</h2>
        <ResponsiveContainer width="100%" height={300}>
          <LineChart data={eventHistory}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="timestamp" />
            <YAxis />
            <Tooltip />
            <Legend />
            <Line type="monotone" dataKey="count" stroke="#8884d8" />
          </LineChart>
        </ResponsiveContainer>
      </div>

      <div>
        <h2>Event Types Distribution</h2>
        <ResponsiveContainer width="100%" height={300}>
          <BarChart data={eventHistory}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="event_type" />
            <YAxis />
            <Tooltip />
            <Legend />
            <Bar dataKey="count" fill="#82ca9d" />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}



