import React, { useEffect, useState } from 'react';
import { GameLoop } from '../engine/GameLoop';
import { generateHexGrid } from '../systems/HexGrid';
import { createGameState } from '../../states/gameState';

export const MainGameScene = () => {
    const [store] = useState(() => {
      const hexes = generateHexGrid(20);
      return createGameState(hexes);
    });
    
    // useEffect(() => {
    //   const loop = new GameLoop(store);
    //   loop.start();
    //   return () => loop.stop();
    // }, [store]);
  };