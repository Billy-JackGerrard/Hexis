import React, { useState, useRef, useEffect } from 'react';
import { HexGrid, Layout, Hexagon } from 'react-hexgrid';

const MOUSE_LEFT = 0;
const MOUSE_MIDDLE = 1;
const MOUSE_RIGHT = 2;

const HEX_NUM = 5;

const HexMap = () => {
    
    const [dragging, setDragging] = useState(false);
    const [startPos, setStartPos] = useState({ x: 0, y: 0 });
    const [offset, setOffset] = useState({ x: 0, y: 0 });

    const [scale, setScale] = useState(1);
    const [transformOrigin, setTransformOrigin] = useState('0 0'); // Default to top-left

    const hexagons = [];

    // Generate a simple hex grid
    for (let q = -HEX_NUM; q <= HEX_NUM; q++) {
        for (let r = -HEX_NUM; r <= HEX_NUM; r++) {
            const s = -q - r;
            if (Math.abs(s) <= HEX_NUM) {
            hexagons.push({ q, r, s });
      }
    }
  }
  //poop
  const handleMouseDown = (e) => {
    if (e.button === MOUSE_LEFT) {
      setDragging(true);
      setStartPos({ x: e.clientX, y: e.clientY });
      e.preventDefault(); // Prevent context menu
    }
  };

  const handleMouseMove = (e) => {
    if (dragging) {
      const dx = e.clientX - startPos.x;
      const dy = e.clientY - startPos.y;
      setOffset((prevOffset) => ({
        x: prevOffset.x + dx,
        y: prevOffset.y + dy,
      }));
      setStartPos({ x: e.clientX, y: e.clientY });
    }
  };

  const handleMouseUp = () => {
    setDragging(false);
  };

  const handleWheel = (e) => {
  e.preventDefault();
  const zoomIntensity = 0.1;
  const newScale = e.deltaY < 0 ? scale + zoomIntensity : scale - zoomIntensity;

  // Clamp zoom level between 0.5x and 3x
  setScale(Math.min(3, Math.max(0.5, newScale)));

  // Calculate the mouse position relative to the container
  const containerRect = e.currentTarget.getBoundingClientRect();
  const mouseX = e.clientX - containerRect.left;
  const mouseY = e.clientY - containerRect.top;

  // Set the transform origin to where the mouse is
  setTransformOrigin(`${mouseX}px ${mouseY}px`);
};
  

    // Add event listeners when component mounts
    useEffect(() => {
    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
    window.addEventListener('mousedown', handleMouseDown);

    return () => {
        window.removeEventListener('mousemove', handleMouseMove);
        window.removeEventListener('mouseup', handleMouseUp);
        window.removeEventListener('mousedown', handleMouseDown);
    };
    }, [dragging, startPos]);

    return (
      <div
        onWheel={handleWheel}
        style={{
          width: '100vw',
          height: '100vh',
          cursor: dragging ? 'grabbing' : 'grab',
          overflow: 'hidden',
          position: 'relative',
          userSelect: 'none',
        }}
      >
        <div
          style={{
            position: 'absolute',
            top: offset.y,
            left: offset.x,
            transform: `scale(${scale})`,
            transformOrigin: transformOrigin, // Dynamically set based on mouse position
            transition: 'transform 0.1s ease', // Smooth zooming
          }}
        >
          <HexGrid width={2000} height={2000}>
            <Layout size={{ x: 2, y: 2 }} flat={false} spacing={1.1} origin={{ x: 0, y: 0 }}>
              {hexagons.map(({ q, r, s }, i) => (
                <Hexagon key={i} q={q} r={r} s={s} />
              ))}
            </Layout>
          </HexGrid>
        </div>
      </div>
    );
    
    };

export default HexMap;
