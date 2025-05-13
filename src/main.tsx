import React from "react";
import ReactDOM from 'react-dom/client';
import mainGame from './scenes/mainGame';
// import './index.css'; // Global styles


// Create the root element and render the App component inside it

ReactDOM.createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
      <mainGame/>
    </React.StrictMode>
  );