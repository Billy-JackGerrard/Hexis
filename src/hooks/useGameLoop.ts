import { useEffect } from 'react';

export const useGameLoop = (update: (deltaTime: number) => void) => {
  useEffect(() => {
    let lastTime = performance.now();
    let frameId: number;

    const loop = (currentTime: number) => {
      const deltaTime = (currentTime - lastTime) / 1000; // Convert to seconds
      lastTime = currentTime;
      update(deltaTime);
      frameId = requestAnimationFrame(loop);
    };

    frameId = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(frameId); // Cleanup on unmount
  }, [update]);
};