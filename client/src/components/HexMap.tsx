import React, { useState, useMemo, useRef, useEffect } from 'react';
import { HexGrid, Layout, Hexagon } from 'react-hexgrid';
import { ReactSVGPanZoom, Value, Tool } from 'react-svg-pan-zoom';
import { useGameStore } from '../store/useGameStore';
import { Hex, HexType } from '../types/game';

// Constants (component-specific, related to rendering)
const HEX_NUM = 20; // Grid radius
const HEX_SIZE = 1.5; // Visual size of hexes
const CANVAS_SIZE_MULTIPLIER = 1; // Responsive scaling
const MAX_ZOOM = 3; // Maximum zoom level
const MIN_ZOOM = 0.5; // Minimum zoom level

// Calculate grid boundaries based on your hex layout
const GRID_WIDTH = HEX_NUM * 2 * HEX_SIZE * 1.5; // Approximate width in SVG units
const GRID_HEIGHT = HEX_NUM * 2 * HEX_SIZE * Math.sqrt(3); // Approximate height


// interface for HexMap component
interface HexMapProps {
    hexagons: Record<string, Hex>;
  }


const HexMap: React.FC<HexMapProps> = () => {

  // Refs and State
  const viewerRef = useRef<ReactSVGPanZoom>(null);
  const [currentTool, setCurrentTool] = useState<Tool>('auto');
  const [clickedHex, setClickedHex] = useState<string | null>(null);
  const [hoveredHex, setHoveredHex] = useState<string | null>(null);
  const [viewerValue, setViewerValue] = useState<Value | null>(null);

  // Zustand Store
  const { hexagons, setGameState } = useGameStore();

//   // Initialize default viewer value on mount
//   useEffect(() => {
//     if (viewerRef.current) {
//       const defaultValue = viewerRef.current.getDefaultValue();
//       setViewerValue(defaultValue);
//     }
//   }, []);
  
  // Viewer - adding constraint to prevent panning and zooming out of bounds
  const handleChangeValue = (newValue: Value) => {
    // Calculate visible area based on current zoom
    const visibleWidth = window.innerWidth / newValue.a;
    const visibleHeight = window.innerHeight / newValue.a;
    
    // Calculate max pan based on grid size and visible area
    const maxPanX = Math.max(0, (GRID_WIDTH - visibleWidth) / 2);
    const maxPanY = Math.max(0, (GRID_HEIGHT - visibleHeight) / 2);
    
    // Constrain panning
    newValue.e = Math.max(-maxPanX, Math.min(maxPanX, newValue.e));
    newValue.f = Math.max(-maxPanY, Math.min(maxPanY, newValue.f));
    
    // Constrain zoom
    newValue.a = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, newValue.a));
    newValue.d = newValue.a; // Maintain aspect ratio
    
    setViewerValue(newValue);
  };


  // Initialize Hex Grid
  useEffect(() => {
    const initialHexes: Record<string, Hex> = {};

    // Generate hex grid data
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

  // Window Resize Handler
  useEffect(() => {
    const handleResize = () => {
      if (viewerRef.current) {
        viewerRef.current.fitToViewer();
      }
    };

    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  // Convert hexagons object to array for rendering
  const hexArray = useMemo(() => {
    return Object.entries(hexagons).map(([key, hex]) => ({
      key,
      ...hex.coords
    }));
  }, [hexagons]);

  return (
    <div style={{ width: '100vw', height: '100vh' }}>
      <ReactSVGPanZoom
        ref={viewerRef}
        width={window.innerWidth}
        height={window.innerHeight}
        value={viewerValue}
        onChangeValue={setViewerValue}
        tool={currentTool}
        onChangeTool={setCurrentTool}
        detectAutoPan={true}
        scaleFactorMin={MIN_ZOOM}
        scaleFactorMax={MAX_ZOOM}
        miniatureProps={{
            position: 'left',
            background: 'transparent',
            width: 100,
            height: 100,
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
                  onClick={() => {
                    console.log('Clicked hex:', key, hexagons[key]);
                    setClickedHex(key);
                  }}
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
      </ReactSVGPanZoom>
    </div>
  );
};

export default HexMap;