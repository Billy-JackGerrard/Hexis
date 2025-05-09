import React, { useState, useMemo, useCallback, useRef, useEffect } from 'react';
import { HexGrid, Layout, Hexagon } from 'react-hexgrid';
import { ReactSVGPanZoom } from "react-svg-pan-zoom";


// easy access variables defined here - feel free to change to customise your experience

// hex and canvas settings. HEX_NUM is how many hexes are there in one direction away from the central hex - basically the radius
const HEX_NUM = 20;
const HEX_SIZE = 1.5;
const CANVAS_SIZE_MULTIPLIER = 2;
const MIN_CANVAS_SIZE = 0;

// tile types
const LAND = 0;
const BASE = 1;
const OBSTACLE = 2;


// main function

const HexMap = () => {

  // initialisation
  
  const Viewer = useRef(null);

  const [hoveredHex, setHoveredHex] = useState(null);
  const [clickedHex, setClickedHex] = useState(null);

  const dragMovedRef = useRef(false);


  useEffect(() => {
    if (Viewer.current) {
      Viewer.current.fitToViewer()
    }
  }, []);
  

  // viewer is what the user sees - whats actually on the screen
  const [viewerSize, setViewerSize] = useState({
    width: window.innerWidth,
    height: window.innerHeight,
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
        
        info[key] = {
          coords: {q:q, r:r, s:s},
          terrain: "null",
          type: [Math.abs(q), Math.abs(r), Math.abs(s)].includes(Math.abs(HEX_NUM)) ? OBSTACLE : LAND, // all edge tiles are obstacles, other tiles are land tiles
          resources: {wood: 0, stone: 0, water: 0, food: 0} // add more if necessary
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
        tool="auto"
        detectAutoPan={true}
        miniaturePosition="none"
      >
        <svg width={2000} height={1500}>
          <HexGrid width={3000} height={3000}>
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
                
                const isHovered = hoveredHex === key;
                const isClicked = clickedHex === key;
                return (
                  <Hexagon
                    key={key}
                    q={q}
                    r={r}
                    s={s}
                    
                    onMouseEnter={() => setHoveredHex(key)}
                    onMouseLeave={() => setHoveredHex(null)}
                    onClick={() => {
                      console.log(key);
                      if (!dragMovedRef.current) {
                        setClickedHex(key);
                      }
                    }}
                    
                    style={{
                      //if clicked, tomato colour. if hovered, gold colour. else colour depends on tile type (purple for base, green for land, grey for obstacle)
                      fill: isClicked
                            ? 'tomato'
                            : isHovered
                              ? 'gold'
                              : hexInfo[key].type === BASE
                                ? 'purple'
                                : hexInfo[key].type === LAND
                                  ? 'green'
                                  : 'grey'
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
