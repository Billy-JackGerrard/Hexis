import React, { useEffect, useState } from 'react';
import { GameLoop } from '../engine/gameLoop';
import { generateHexGrid } from '../systems/HexGrid';
import { createGameStore } from '../../states/gameStore';
import { useStore } from 'zustand';

export const MainGameScene = () => {

    // creating the gameStore. only done once, at the start
    const [store] = useState(() => {  
      const hexes = generateHexGrid(20);
      return createGameStore(hexes);
    });
    
    // starting the loop
    useEffect(() => {
      const loop = new GameLoop(store);
      loop.start();
      return () => loop.stop();
    }, [store]);

    // Get state from store for rendering
    const grid = useStore(store, (state) => state.grid);

    return (
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(20, 1fr)' }}>
        {Object.entries(grid).map(([key, hex]) => (
          <div
            key={key}
            style={{
              width: 30,
              height: 30,
              border: '1px solid black'
            }}
          >
          </div>
        ))}
      </div>
    );

  };