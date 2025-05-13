
import React, { useEffect } from 'react';
import { GameLoop } from '../engine/GameLoop';
import { initialiseMap } from '../features/map/mapManager';

export default function MainGame() {

    // initialise the game loop
    useEffect(() => {
        const game = new GameLoop();
        game.start();
        return () => game.stop();
      }, []);
  
  
    return (
    <div className="game-scene">
        <initialiseMap />
        {/* Other game UI */}
    </div>
    );
}
