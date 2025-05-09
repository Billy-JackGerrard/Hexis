import React, { useState, useMemo, useRef, useEffect } from 'react';
import { HexGrid, Layout, Hexagon } from 'react-hexgrid';
import { UncontrolledReactSVGPanZoom, Value } from 'react-svg-pan-zoom';
import { useGameStore } from '../store/useGameStore';
import { Hex, HexType } from '../types/game';

// Constants
const HEX_NUM = 20;
const HEX_SIZE = 1.5;
const CANVAS_SIZE_MULTIPLIER = 1;
const MAX_ZOOM = 3;
const MIN_ZOOM = 0.5;
const GRID_WIDTH = HEX_NUM * 2 * HEX_SIZE * 1.5;
const GRID_HEIGHT = HEX_NUM * 2 * HEX_SIZE * Math.sqrt(3);

interface HexMapProps {
  hexagons: Record<string, Hex>;
}

const HexMap: React.FC<HexMapProps> = () => {
  const viewerRef = useRef<any>(null);
  const [clickedHex, setClickedHex] = useState<string | null>(null);
  const [hoveredHex, setHoveredHex] = useState<string | null>(null);

  const { hexagons, setGameState } = useGameStore();

  // Initialize hex grid
  useEffect(() => {
    const initialHexes: Record<string, Hex> = {};
    for (let q = -HEX_NUM; q <= HEX_NUM; q++) {
      for (let r = -HEX_NUM; r <= HEX_NUM; r++) {
        const s = -q - r;
        if (Math.abs(s) > HEX_NUM) continue;

        const key = `${q},${r},${s}`;
        const isObstacle = [Math.abs(q), Math.abs(r), Math.abs(s)].includes(HEX_NUM);

        initialHexes[key] = {
          coords: { q, r, s },
          type: isObstacle ? HexType.OBSTACLE : HexType.LAND,
          resources: { wood: 0, stone: 0, water: 0, food: 0 },
          colour: isObstacle ? 'gray' : 'green'
        };
      }
    }
    setGameState({ hexagons: initialHexes });
  }, [setGameState]);

  // Handle window resize
  useEffect(() => {
    const handleResize = () => viewerRef.current?.fitToViewer();
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  // Constrain panning to grid boundaries
  const handleChangeValue = (newValue: Value) => {
    const visibleWidth = window.innerWidth / newValue.a;
    const visibleHeight = window.innerHeight / newValue.a;
    const maxPanX = Math.max(0, (GRID_WIDTH * 1.1 - visibleWidth) / 2);
    const maxPanY = Math.max(0, (GRID_HEIGHT * 1.1 - visibleHeight) / 2);

    return {
      ...newValue,
      e: Math.max(-maxPanX, Math.min(maxPanX, newValue.e)),
      f: Math.max(-maxPanY, Math.min(maxPanY, newValue.f))
    };
  };

  // Convert hexagons to array
  const hexArray = useMemo(() => (
    Object.entries(hexagons).map(([key, hex]) => ({ key, ...hex.coords }))
  ), [hexagons]);

  // Optional: Reset view function
  const resetView = () => {
    viewerRef.current?.fitToViewer();
  };

  return (
    <div style={{ width: '100vw', height: '100vh' }}>
      <UncontrolledReactSVGPanZoom
        ref={viewerRef}
        width={window.innerWidth}
        height={window.innerHeight}
        onChangeValue={handleChangeValue}
        scaleFactorMin={MIN_ZOOM}
        scaleFactorMax={MAX_ZOOM}
        detectAutoPan={true}
        miniatureProps={{
          position: 'left',
          background: 'transparent',
          width: 100,
          height: 100
        }}
      >
        <svg
          width={window.innerWidth * CANVAS_SIZE_MULTIPLIER}
          height={window.innerHeight * CANVAS_SIZE_MULTIPLIER}
          style={{ overflow: 'hidden', display: 'block' }}
        >
          <HexGrid
            width={window.innerWidth * CANVAS_SIZE_MULTIPLIER}
            height={window.innerHeight * CANVAS_SIZE_MULTIPLIER}
          >
            <Layout
              size={{ x: HEX_SIZE, y: HEX_SIZE }}
              flat={false}
              spacing={1}
              origin={{ x: 0, y: 0 }}
            >
              {hexArray.map(({ key, q, r, s }) => (
                <Hexagon
                  key={key}
                  q={q}
                  r={r}
                  s={s}
                  onClick={() => setClickedHex(key)}
                  onMouseEnter={() => setHoveredHex(key)}
                  onMouseLeave={() => setHoveredHex(null)}
                  style={{
                    fill: clickedHex === key ? 'tomato' : hexagons[key].colour,
                    stroke: hoveredHex === key ? 'white' : 'none',
                    strokeWidth: '2px',
                    transition: 'fill 0.2s ease'
                  }}
                />
              ))}
            </Layout>
          </HexGrid>
        </svg>
      </UncontrolledReactSVGPanZoom>

      {/* Optional reset button */}
      <button 
        onClick={resetView}
        style={{
          position: 'absolute',
          bottom: '20px',
          right: '20px',
          padding: '10px',
          zIndex: 100
        }}
      >
        Reset View
      </button>
    </div>
  );
};

export default HexMap;