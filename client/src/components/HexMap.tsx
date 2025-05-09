import React, { useState, useMemo, useRef, useEffect } from 'react';
import { HexGrid, Layout, Hexagon } from 'react-hexgrid';
import { ReactSVGPanZoom, Value, Tool } from 'react-svg-pan-zoom';
import { useGameStore } from '../store/useGameStore';
import { Hex, HexType } from '../types/game';

// Constants (component-specific, related to rendering)
const HEX_NUM = 20; // Grid radius
const HEX_SIZE = 1.5; // Visual size of hexes
const CANVAS_SIZE_MULTIPLIER = 1; // Responsive scaling

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
        scaleFactorMin={0.5}
        scaleFactorMax={5}
        miniatureProps={{
            position: 'none',
            background: 'transparent',
            width: 100,
            height: 100,
          }}
      >
        <svg
          width={window.innerWidth * CANVAS_SIZE_MULTIPLIER}
          height={window.innerHeight * CANVAS_SIZE_MULTIPLIER}
          style={{ overflow: 'visible', display: 'block' }}
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
                    fill: clickedHex === key ? 'gold' : hexagons[key].colour,
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