import { useEffect, useState } from 'react';
import { GameLoop } from '../engine/gameLoop';
import { gameStore } from '../../stores/gameStore';
import { useStore } from 'zustand';

export const MainGameScene = () => {

    // creating the gameStore. only done once, at the start
    const [store] = useState(() => {
      return gameStore;
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
        /{Object.entries(grid).map(([key, hex]) => (
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