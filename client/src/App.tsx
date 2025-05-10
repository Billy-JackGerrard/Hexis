import React from 'react';
import HexGrid from './components/HexMap';
import { generateHexGrid } from './game/systems/HexGrid';

const App: React.FC = () => {
  generateHexGrid(20);

  return (
    <div className="app">
    </div>
  );
};

export default App;