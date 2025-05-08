import React, { useState, useMemo, useCallback, useRef } from 'react';
import { HexGrid, Layout, Hexagon } from 'react-hexgrid';

const MOUSE_LEFT = 0;
const HEX_NUM = 20;
const ZOOM_INTENSITY = 0.05;
const MIN_SCALE = 0.5;
const MAX_SCALE = 3;

const HexMap = () => {
  const [dragging, setDragging] = useState(false);
  const startPosRef = useRef({ x: 0, y: 0 });
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const [scale, setScale] = useState(1);
  const [transformOrigin, setTransformOrigin] = useState('0 0');
  const containerRef = useRef(null);
  const lastPosRef = useRef({ x: 0, y: 0 });

  const [hoveredHex, setHoveredHex] = useState(null);
  const [clickedHex, setClickedHex] = useState(null);

  const hexagons = useMemo(() => {
    const h = [];
    for (let q = -HEX_NUM; q <= HEX_NUM; q++) {
      for (let r = -HEX_NUM; r <= HEX_NUM; r++) {
        const s = -q - r;
        if (Math.abs(s) <= HEX_NUM) {
          h.push({ q, r, s });
        }
      }
    }
    return h;
  }, []);

  const handleMouseDown = useCallback((e) => {
    if (e.button === MOUSE_LEFT) {
      setDragging(true);
      startPosRef.current = { x: e.clientX, y: e.clientY };
      e.preventDefault();
    }
  }, []);

  const handleMouseMove = useCallback((e) => {
    if (dragging) {
      const dx = e.clientX - startPosRef.current.x;
      const dy = e.clientY - startPosRef.current.y;
      setOffset((prev) => ({ x: prev.x + dx, y: prev.y + dy }));
      startPosRef.current = { x: e.clientX, y: e.clientY };
    }
  }, [dragging]);

  const handleMouseUp = useCallback(() => {
    setDragging(false);
  }, []);


  // Zoom function
  const handleWheel = useCallback((e) => {
    e.preventDefault();
  
    const rect = containerRef.current.getBoundingClientRect();
    const mouseX = e.clientX - rect.left - offset.x;
    const mouseY = e.clientY - rect.top - offset.y;
  
    const wheel = e.deltaY < 0 ? 1 : -1;
    const newScale = scale + wheel * ZOOM_INTENSITY;
    const clampedScale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, newScale));
  
    if (clampedScale !== scale) {
      const ratio = clampedScale / scale;
  
      const newOffset = {
        x: offset.x - mouseX * (ratio - 1),
        y: offset.y - mouseY * (ratio - 1),
      };
  
      setScale(clampedScale);
      setOffset(newOffset);
    }
  }, [scale, offset]);
  
  

  const handleTouchStart = useCallback((e) => {
    if (e.touches.length === 1) {
      const touch = e.touches[0];
      setDragging(true);
      startPosRef.current = { x: touch.clientX, y: touch.clientY };
    }
  }, []);

  const handleTouchMove = useCallback((e) => {
    if (dragging && e.touches.length === 1) {
      const touch = e.touches[0];
      const dx = touch.clientX - startPosRef.current.x;
      const dy = touch.clientY - startPosRef.current.y;
      setOffset((prev) => ({ x: prev.x + dx, y: prev.y + dy }));
      startPosRef.current = { x: touch.clientX, y: touch.clientY };
    }
  }, [dragging]);

  const handleTouchEnd = useCallback(() => {
    setDragging(false);
  }, []);

  return (
    <div
      ref={containerRef}
      onMouseDown={handleMouseDown}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
      onWheel={handleWheel}
      onTouchStart={handleTouchStart}
      onTouchMove={handleTouchMove}
      onTouchEnd={handleTouchEnd}
      style={{
        width: '100vw',
        height: '100vh',
        cursor: dragging ? 'grabbing' : 'grab',
        overflow: 'hidden',
        position: 'relative',
        userSelect: 'none',
        touchAction: 'none',
      }}
    >
      <div
        style={{
          position: 'absolute',
          transform: `translate(${offset.x}px, ${offset.y}px)`,
        }}
      >
        <div
          style={{
            transform: `scale(${scale})`,
            transformOrigin: transformOrigin,
          }}
        >
          <HexGrid width={2000} height={2000}>
            <Layout size={{ x: 1, y: 1 }} flat={false} spacing={1} origin={{ x: 0, y: 0 }}>
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
                    onClick={() => setClickedHex(key)}
                    style={{
                      fill: isClicked ? 'tomato' : isHovered ? 'gold' : 'lightgrey',
                    }}
                  />
                );
              })}
            </Layout>
          </HexGrid>
        </div>
      </div>
    </div>
  );
};

export default HexMap;
