
// src/scenes/mainGame.tsx
import { useEffect, useRef } from 'react'
import renderMap from '../rendering/renderMap'
// import generateMap from '../game-mechanics/generateMapData'

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

    // const map = generateMap() 

    (async () => {
      await renderMap();
    })();
  


    return () => {
      // app.destroy(true, { children: true }) // Clean up
    }
  }, [])

  return <div ref={containerRef} style={{ width: '100%', height: '100%' }} />
}
