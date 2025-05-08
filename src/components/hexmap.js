import React, { useState, useRef, useEffect } from 'react';
import { HexGrid, Layout, Hexagon } from 'react-hexgrid';

const MOUSE_LEFT = 0;
const MOUSE_MIDDLE = 1;
const MOUSE_RIGHT = 2;

const HexMap = () => {
    
    const [dragging, setDragging] = useState(false);
    const [startPos, setStartPos] = useState({ x: 0, y: 0 });
    const [offset, setOffset] = useState({ x: 0, y: 0 });

    const hexagons = [];

    // Generate a simple hex grid
    for (let q = -5; q <= 5; q++) {
        for (let r = -5; r <= 5; r++) {
            const s = -q - r;
            if (Math.abs(s) <= 5) {
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
          style={{
            width: '100vw',
            height: '100vh',
            cursor: dragging ? 'grabbing' : 'grab',
            overflow: 'hidden',
            position: 'relative',
          }}
        >
          <HexGrid width={2000} height={2000} style={{ position: 'absolute', top: offset.y, left: offset.x }}>
            <Layout size={{ x: 2, y: 2 }} flat={false} spacing={1.1} origin={{ x: 0, y: 0 }}>
              {hexagons.map(({ q, r, s }, i) => (
                <Hexagon key={i} q={q} r={r} s={s} />
              ))}
            </Layout>
          </HexGrid>
        </div>
      );
    };

export default HexMap;
