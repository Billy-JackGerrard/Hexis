import React from 'react';
import ReactDOM from 'react-dom/client';


// 2. Combined App component (no separate file needed)
function App() {
  return (
    <div style={{ position: 'relative', width: '100vw', height: '100vh' }}>
      {/* Phaser canvas will mount here */}
      <div id="game-container" />
      
      {/* React UI overlays (position absolutely) */}
      <div style={{
        position: 'absolute',
        top: 10,
        left: 10,
        color: 'white',
        pointerEvents: 'none' // Allows clicks to pass through to Phaser
      }}>
        {/* Example UI element */}
        <h1>React UI Overlay</h1>


      </div>
    </div>
  );
}

// 3. Render
ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);