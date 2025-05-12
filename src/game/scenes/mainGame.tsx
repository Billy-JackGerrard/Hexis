
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
      



    </div>
  );
}
