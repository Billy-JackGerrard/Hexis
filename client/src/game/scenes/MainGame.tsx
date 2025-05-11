import React, { useEffect, useState } from 'react';
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
      <div >
        <p>Poop</p>
      </div>
    );

  };