// Accepts connections on 127.0.0.1:8765 and never answers, so the update check in the app
// (https://10.0.2.2:8765 from the Android emulator) hangs until `fallbackToCacheTimeout` runs out.
const net = require('net');

const held = [];
net
  .createServer((socket) => {
    held.push(socket);
    socket.on('error', () => {});
  })
  .listen(8765, '127.0.0.1', () => console.log('holding connections on 127.0.0.1:8765, Ctrl+C to stop'));
