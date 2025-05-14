import React from "react";
import ReactDOM from 'react-dom/client';
import MainGame from './scenes/MainGame';
// import './index.css'; // Global styles


// Create the root element and render the App component inside it

ReactDOM.createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
        <MainGame />
    </React.StrictMode>
  );