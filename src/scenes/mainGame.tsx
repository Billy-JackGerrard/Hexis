
// src/scenes/mainGame.tsx
import { useEffect, useRef } from 'react'
import renderMap from '../rendering/renderMap'
// import generateMap from '../game-mechanics/generateMapData'

export default function MainGame() {
  
    const containerRef = useRef<HTMLDivElement>(null)
  
    useEffect(() => {
      if (!containerRef.current) return
      renderMap(containerRef.current)
    }, [])
  
    return <div ref={containerRef} style={{ width: '100vw', height: '100vh' }} />
}
