import { Server } from 'socket.io';

const io = new Server(3000, {
  cors: { origin: "*" } // Allow all clients (adjust in production)
});

io.on('connection', (socket) => {
  console.log('Player connected:', socket.id);



  // Handle troop movements - EXAMPLE
  socket.on('MOVE_TROOP', (data) => {
    // Broadcast to all other players
    socket.broadcast.emit('TROOP_MOVED', data);
  });


  
  socket.on('disconnect', () => {
    console.log('Player disconnected:', socket.id);
  });
});