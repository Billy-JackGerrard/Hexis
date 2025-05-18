
import { useEffect, useRef } from 'react'
import renderMap from '../map/renderMap'

export default function MainGame() {
  const containerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
      if (!containerRef.current) return

      // Create the map and store cleanup function
      const destroy = renderMap(containerRef.current)
      
  }, [])
  
    return <div ref={containerRef} style={{
      width: '100vw',
      height: '100vh',
      display: 'block',
      overflow: 'auto',
      position: 'fixed',
      scrollbarGutter: 'stable'
    }} />
}
