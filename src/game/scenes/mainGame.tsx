
import React, { useEffect } from 'react';
import { useGameStore } from '../../stores/gameStore';
import { useGameLoop } from '../../hooks/useGameLoop';

export default function MainGame() {
  const { grid, updateHexBuilding } = useGameStore(
    (state) => ({
      grid: state.grid,
      updateHexBuilding: state.updateHexBuilding,
    })
  );

  useGameLoop(); // Starts the game loop on mount

  useEffect(() => {
    // This is run whenever grid changes.
    
  }, [grid]);

  return (
    <div>
      <h1>Hex Strategy Game</h1>
      {/* Render hexes or map here, passing updateHexBuilding to child components if needed */}
    </div>
  );
}
