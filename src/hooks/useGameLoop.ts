import { useEffect } from 'react';
import { GameLoop } from '../game/engine/gameLoop';


/**
 * A hook that handles the initialization, starting, and stopping of the game loop
 * @returns 
 */
export function useGameLoop() {
  const gameLoop = new GameLoop();

  useEffect(() => {
    gameLoop.start();
    return () => gameLoop.stop();
  }, [gameLoop]);

  return {
    start: gameLoop.start,
    stop: gameLoop.stop,
  };
}






// OLD VERSION: not working, but kept because it has some functionality that might be useful later - pause/resume etc


// import { useEffect, useRef } from 'react';

// import { GameLoop } from '../game/engine/gameLoop';
// import { useGameStore } from '../stores/gameStore';

// /**
//  * Custom hook to manage the game loop lifecycle
//  * @param options Configuration for the game loop
//  * @param options.pauseWhenHidden Pauses loop when tab is inactive (default: true)
//  */
// export const useGameLoop = (options = { pauseWhenHidden: true }) => {
//   const gameLoopRef = useRef<GameLoop | null>(null);
  
//   const isRunning = useGameStore(state => state.isRunning);

//   // Initialize game loop - only ran once
//   useEffect(() => {
//     const loop = new GameLoop(gameStore);
//     gameLoopRef.current = loop;

//     // Handle tab visibility changes
//     const handleVisibilityChange = () => {
//       if (!options.pauseWhenHidden) return;
//       if (document.hidden) {
//         loop.stop();
//         isActiveRef.current = false;
//       } else if (isActiveRef.current) {
//         loop.start();
//       }
//     };

//     document.addEventListener('visibilitychange', handleVisibilityChange);
//     loop.start();

//     return () => {
//       loop.stop();
//       document.removeEventListener('visibilitychange', handleVisibilityChange);
//     };
//   }, [options.pauseWhenHidden]);

//   // Expose controls
//   return {
//     pause: () => {
//       isActiveRef.current = false;
//       gameLoopRef.current?.stop();
//     },
//     resume: () => {
//       isActiveRef.current = true;
//       gameLoopRef.current?.start();
//     },
//   };
// };
 