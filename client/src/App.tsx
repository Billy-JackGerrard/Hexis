import React from 'react';
import HexGrid from './components/HexMap';
import { useGameStore } from './store/useGameStore';

const App: React.FC = () => {
  const { hexagons } = useGameStore();

  return (
    <div className="app">
      <HexGrid hexagons={hexagons} />
    </div>
  );
};

export default App;