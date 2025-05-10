import React, { useState, useMemo, useRef, useEffect } from 'react';
import { HexGrid, Layout, Hexagon } from 'react-hexgrid';
import { UncontrolledReactSVGPanZoom, Value } from 'react-svg-pan-zoom';
import { useGameStore } from '../store/gameState';
import { Hex, HexType } from '../types';


// TO DO
// Move reset button to the toolbar at the top right
// disable panning out of bounds
// disable the click mode and the drag mode
// enlarge the map so when loaded, the map is bigger than the viewport
// be able to unclick a hex

// Constants
const HEX_NUM = 20;
const HEX_SIZE = 2;
const CANVAS_SIZE_MULTIPLIER = 2;
const MAX_ZOOM = 3;
const MIN_ZOOM = 0.5;
const HEX_HORIZONTAL_SPACING = HEX_SIZE * 2 * 0.75;
const HEX_VERTICAL_SPACING = HEX_SIZE * Math.sqrt(3);
const GRID_WIDTH = (HEX_NUM * 2 + 1) * HEX_HORIZONTAL_SPACING;
const GRID_HEIGHT = (HEX_NUM * 2 + 1) * HEX_VERTICAL_SPACING;

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

    // 1. Calculate visible area in SVG units
    const visibleWidth = window.innerWidth / newValue.a;
    const visibleHeight = window.innerHeight / newValue.a;

    // 2. Calculate effective grid boundaries (accounting for center origin)
    const gridLeft = -GRID_WIDTH/2;
    const gridRight = GRID_WIDTH/2;
    const gridTop = -GRID_HEIGHT/2; 
    const gridBottom = GRID_HEIGHT/2;

    // 3. Calculate min/max translation (e,f) to keep viewport within grid
    const minX = gridLeft + visibleWidth/2;
    const maxX = gridRight - visibleWidth/2;
    const minY = gridTop + visibleHeight/2;
    const maxY = gridBottom - visibleHeight/2;

    return {
      ...newValue,
      e: Math.max(minX, Math.min(maxX, newValue.e)),
      f: Math.max(minY, Math.min(maxY, newValue.f))
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
          style={{ overflow: 'visible', display: 'block'}}
        >
          <HexGrid
            width={window.innerWidth * CANVAS_SIZE_MULTIPLIER}
            height={window.innerHeight * CANVAS_SIZE_MULTIPLIER}
            color='blue'
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

          {/* 1. HexGrid boundary (SVG coordinates) */}
          <rect
            x={-GRID_WIDTH/2}
            y={-GRID_HEIGHT/2}
            width={GRID_WIDTH}
            height={GRID_HEIGHT}
            fill="none"
            stroke="red"
            strokeWidth={10}
            strokeDasharray="20,10"
          />
              
          {/* 2. SVG viewport boundary (pixel coordinates) */}
          <rect
            x={-window.innerWidth/2}
            y={-window.innerHeight/2}
            width={window.innerWidth}
            height={window.innerHeight}
            fill="none"
            stroke="blue"
            strokeWidth={5}
          />

          {/* 3. Center crosshair */}
          <line x1={-50} y1={0} x2={50} y2={0} stroke="green" strokeWidth={1} />
          <line x1={0} y1={-50} x2={0} y2={50} stroke="green" strokeWidth={1} />

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

      {/* This is for testing  */}
      <rect 
        x={-GRID_WIDTH/2}
        y={-GRID_HEIGHT/2}
        width={GRID_WIDTH}
        height={GRID_HEIGHT}
        fill="none"
        stroke="red"
        strokeWidth="10"
      />
    </div>
    
  );
};

export default HexMap;