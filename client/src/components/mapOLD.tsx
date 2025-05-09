import React, { useState, useMemo, useCallback, useRef, useEffect } from 'react';
import { HexGrid, Layout, Hexagon } from 'react-hexgrid';
import { ReactSVGPanZoom } from "react-svg-pan-zoom";
import { Hex } from '../types'; 


// easy access variables defined here - feel free to change to customise your experience

// hex and canvas settings. HEX_NUM is how many hexes are there in one direction away from the central hex - basically the radius
const HEX_NUM = 20;
const HEX_SIZE = 1.5;
const CANVAS_SIZE_MULTIPLIER = 1;
const MIN_CANVAS_SIZE = 0;

// tile types
const LAND = 0;
const BASE = 1;
const OBSTACLE = 2;



interface HexMapProps {
  hexagons: Record<string, Hex>;
}


// main function

const HexMap: React.FC<HexMapProps> = () => {

  // initialisation
  
  const Viewer = useRef(null);

  const [hoveredHex, setHoveredHex] = useState(null);
  const [clickedHex, setClickedHex] = useState(null);

  // viewer is what the user sees - whats actually on the screen
  const [viewerSize, setViewerSize] = useState({
    width: window.innerWidth,
    height: window.innerHeight,
  });

  // Set the initial zoom and position values
  const [viewerValue, setViewerValue] = useState({
    x: 0,        // initial x position
    y: 0,        // initial y position
    scale: 1,     // initial zoom level (scale)
  });
  
  // in case the window size changes (eg minimising)
  useEffect(() => {
    const handleResize = () => {
      setViewerSize({
        width: window.innerWidth,
        height: window.innerHeight,
      });
    };
  
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  useEffect(() => {
    if (Viewer.current) {
      Viewer.current.fitToViewer()
    }
  }, []);

  

  // creating the hexes, putting them in hexagons. making a dictionary (hexInfo) with all the info of each hex
  const { hexagons, hexInfo} = useMemo(() => {
    const hexArray = [];
    const info = {};

    for (let q = -HEX_NUM; q <= HEX_NUM; q++) {
      for (let r = -HEX_NUM; r <= HEX_NUM; r++) {
        const s = -q - r;
        if (Math.abs(s) <= HEX_NUM) {
          hexArray.push({ q, r, s });
        }
        const key = `${q},${r},${s}`;
        
        // Determine the tile type - all edge tiles are obstacles, other tiles are land tiles
        const type = [Math.abs(q), Math.abs(r), Math.abs(s)].includes(Math.abs(HEX_NUM)) 
        ? OBSTACLE
        : LAND;

        info[key] = {
          coords: {q:q, r:r, s:s},
          terrain: "null",
          type: type,
          resources: {wood: 0, stone: 0, water: 0, food: 0}, // add more if necessary
          colour: type == LAND ? 'green' : 'gray'
        };
      }
    }
    return {hexagons: hexArray, hexInfo: info};
  }, []);

  

  return (
    <div style={{ width: "100vw", height: "100vh" }}>
      <ReactSVGPanZoom
        width={viewerSize.width}
        height={viewerSize.height}
        ref={Viewer}
        value={viewerValue}  // Set the initial value (zoom and position)
        onChangeValue={setViewerValue}  // Handle zoom and pan changes
        tool="auto"  // Automatically handle zooming and panning
        detectAutoPan={true}
        background="blue"
        minScale={0.5}  // Minimum zoom level
        maxScale={5}    // Maximum zoom level
        miniatureProps={{
          miniaturePosition: "none", // replace this with your previous miniaturePosition prop
          miniatureBackground: "transparent", // or any color you prefer
          miniatureWidth: 100, // you can adjust the width as needed
          miniatureHeight: 100, // you can adjust the height as needed
        }}
      >
        <svg
          width={viewerSize.width}
          height={viewerSize.height}
          style={{ overflow: 'visible', display: 'block' }}
        >
          <HexGrid width={viewerSize.width * CANVAS_SIZE_MULTIPLIER} height={viewerSize.height * CANVAS_SIZE_MULTIPLIER}>
            <Layout
              size={{ x: HEX_SIZE, y: HEX_SIZE }}
              flat={false}
              spacing={1}
              origin={{
                x: 0,
                y: 0,
              }}            
            >
              {hexagons.map(({ q, r, s }, i) => {
                const key = `${q},${r},${s}`;

                return (
                  <Hexagon
                    key={key}
                    q={q}
                    r={r}
                    s={s}

                    onClick={() => {
                      console.log(key);
                      setClickedHex(key);
                    }}
                    
                    style={{
                      fill: clickedHex === key ? 'gold' : hexInfo[key].colour
                    }}
                  />
                );
              })}
            </Layout>
          </HexGrid>
        </svg>
      </ReactSVGPanZoom>
      </div>
  );
};

export default HexMap;
