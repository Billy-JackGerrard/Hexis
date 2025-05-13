
// src/scenes/mainGame.tsx
import { useEffect, useRef } from 'react'
// import { initializePixi } from '../rendering/'
import generateMapData from '../game-mechanics/generateMapData'

export default function MainGame() {
  const containerRef = useRef<HTMLDivElement>(null)

  // // initialise the game loop
  // useEffect(() => {
  //   const game = new GameLoop();
  //   game.start();
  //   return () => game.stop();
  // }, []);

  // Initialize PixiJS and generate the map
  useEffect(() => {
    if (!containerRef.current) return

    const map = generateMapData() 

    return () => {
      app.destroy(true, { children: true }) // Clean up
    }
  }, [])

  return <div ref={containerRef} style={{ width: '100%', height: '100%' }} />
}
