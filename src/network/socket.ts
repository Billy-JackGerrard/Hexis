import { io } from 'socket.io-client';
import { gameStore } from '../stores/gameStore';

const socket = io('http://your-server-url');

// Listen for enemy troop movements - EXAMPLE
socket.on('TROOP_MOVED', (data) => {
  gameStore.getState()// .updateEnemyTroop(data);
});

// Send troop movement - EXAMPLE
export const sendTroopMove = (troopId: string, x: number, y: number) => {
  socket.emit('MOVE_TROOP', { troopId, x, y });
};