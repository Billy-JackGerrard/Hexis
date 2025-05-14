
import { useEffect, useRef } from 'react'
import createMap from '../setup/createMap'

export default function MainGame() {
  const containerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
      if (!containerRef.current) return

      // Create the map and store cleanup function
      const destroy = createMap(containerRef.current)
      
  }, [])
  
    return <div ref={containerRef} style={{ width: '100vw', height: '100vh', overflow: 'hidden' }} />
}
