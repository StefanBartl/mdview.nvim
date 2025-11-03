/* Client bootstrapping:
   - Connects to WebSocket on server
   - Receives render updates (html) and injects into container
*/

const socket = new WebSocket(`ws://${location.host}`);

socket.addEventListener('open', () => {
  console.log('connected to mdview server');
});

socket.addEventListener('message', (ev) => {
  try {
    const msg = JSON.parse(ev.data);
    if (msg.type === 'render_update' && typeof msg.payload === 'string') {
      const container = document.getElementById('mdview-root');
      if (container) {
        // replace or patch DOM; initial POC: full replace
        container.innerHTML = msg.payload;
      }
    }
  } catch (err) {
    console.error('invalid message', err);
  }
});
