import React, { useState, useMemo, useCallback, useRef, useEffect } from 'react';
import { HexGrid, Layout, Hexagon } from 'react-hexgrid';


// mouse buttons numbers
const MOUSE_LEFT = 0;
const MOUSE_MIDDLE = 1;
const MOUSE_RIGHT = 2

// hexes. HEX_NUM is how many hexes are there in one direction away from the central hex - basically the radius
const HEX_NUM = 25;
const HEX_SIZE = 1;

// zoom settings
const ZOOM_INTENSITY = 0.05;
const MIN_SCALE = 0.5;
const MAX_SCALE = 3;

// tile types
const LAND = 0;
const BASE = 1;
const OBSTACLE = 2;

const HexMap = () => {

  // initialisation

  const [dragging, setDragging] = useState(false);
  
  const [scale, setScale] = useState(1);
  const [hoveredHex, setHoveredHex] = useState(null);
  const [clickedHex, setClickedHex] = useState(null);

  const dragMovedRef = useRef(false);
  const containerRef = useRef(null);
  const startPosRef = useRef({ x: 0, y: 0 });

  const [offset, setOffset] = useState({ x: 0, y: 0 });

  const [canvasSize, setCanvasSize] = useState({
    width: window.innerWidth,
    height: window.innerHeight,
  });

  // in case the window size changes (eg minimising)
  useEffect(() => {
    const handleResize = () => {
      setCanvasSize({
        width: window.innerWidth,
        height: window.innerHeight,
      });
    };
  
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);
  
  

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


  const handleMouseDown = useCallback((e) => {
    if (e.button === MOUSE_LEFT) {
      setDragging(true);
      dragMovedRef.current = false;
      startPosRef.current = { 
        x: e.clientX, 
        y: e.clientY,
      };
      e.preventDefault();
    }
  }, []);

  const handleMouseMove = useCallback((e) => {
    if (dragging) {
      dragMovedRef.current = true;
      setClickedHex(null);
      setOffset((prev) => ({
        x: prev.x + (e.clientX - startPosRef.current.x),
        y: prev.y + (e.clientY - startPosRef.current.y),
      }));
      startPosRef.current = { x: e.clientX, y: e.clientY };
    }
  }, [dragging]);
  

  const handleMouseUp = useCallback(() => {
    setDragging(false);
  }, []);


  // // Zoom function
  // const handleWheel = useCallback((e) => {
  //   e.preventDefault();
  //   if (!containerRef.current) return;
  
  //   const mouseX = e.clientX;
  //   const mouseY = e.clientY;
  
  //   const wheel = e.deltaY < 0 ? 1 : -1;
  //   const newScale = scale + wheel * ZOOM_INTENSITY;
  //   const clampedScale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, newScale));
  
  //   if (clampedScale === scale) return;
  
  //   // Calculate new offset to zoom toward mouse position
  //   const zoomFactor = clampedScale / scale;
  //   setOffset({
  //     x: mouseX - (mouseX - offset.x),// * zoomFactor,
  //     y: mouseY - (mouseY - offset.y)// * zoomFactor,
  //   });
  //   setScale(clampedScale);
  // }, [scale, offset]);
  
  
  
  

  // const handleTouchStart = useCallback((e) => {
  //   if (e.touches.length === 1) {
  //     const touch = e.touches[0];
  //     setDragging(true);
  //     dragMovedRef.current = false;
  //     startPosRef.current = { x: touch.clientX, y: touch.clientY };
  //   }
  // }, []);

  // const handleTouchMove = useCallback((e) => {
  //   if (dragging && e.touches.length === 1) {
  //     dragMovedRef.current = true;
  //     setClickedHex(null); // Deselect clicked hex on drag
  //     const touch = e.touches[0];
  //     const dx = (touch.clientX - startPosRef.current.x) / scale;
  //     const dy = (touch.clientY - startPosRef.current.y) / scale;
  //     setOffset((prev) => ({
  //       x: prev.x + dx,
  //       y: prev.y + dy,
  //     }));
  //     startPosRef.current = { x: touch.clientX, y: touch.clientY };
  //   }
  // }, [dragging]);
  

  // const handleTouchEnd = useCallback(() => {
  //   setDragging(false);
  // }, []);


  return (
    <div
      ref={containerRef}
      onMouseDown={handleMouseDown}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
      onMouseLeave={handleMouseUp}
      //onWheel={handleWheel}
      // onTouchStart={handleTouchStart}
      // onTouchMove={handleTouchMove}
      // onTouchEnd={handleTouchEnd}
      style={{
        width: '100vw',
        height: '100vh',
        cursor: dragging ? 'grabbing' : 'grab',
        overflow: 'hidden',
        position: 'relative',
        userSelect: 'none',
        touchAction: 'none',
        background: 'blue',
      }}
      >
        <div
        style={{
          position: 'absolute',
          transform: `translate(${offset.x}px, ${offset.y}px)`, // scale(${scale})
        }}
      >
          <HexGrid width={canvasSize.width} height={canvasSize.height}>
          <Layout
            size={{ x: HEX_SIZE, y: HEX_SIZE }}
            flat={false}
            spacing={1}
            origin={{ x: 0, y: 0}}
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
          </div>
        </div>
  );
};

export default HexMap;
