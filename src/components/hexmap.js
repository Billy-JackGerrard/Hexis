import React, { useState, useMemo, useCallback } from 'react';
import { HexGrid, Layout, Hexagon } from 'react-hexgrid';

const MOUSE_LEFT = 0;
const HEX_NUM = 10;

const HexMap = () => {
  const [dragging, setDragging] = useState(false);
  const [startPos, setStartPos] = useState({ x: 0, y: 0 });
  const [offset, setOffset] = useState({ x: 0, y: 0 });

  const [scale, setScale] = useState(1);
  const [transformOrigin, setTransformOrigin] = useState('0 0');

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
      setStartPos({ x: e.clientX, y: e.clientY });
      e.preventDefault();
    }
  }, []);

  const handleMouseMove = useCallback((e) => {
    if (dragging) {
      const dx = e.clientX - startPos.x;
      const dy = e.clientY - startPos.y;
      setOffset((prev) => ({
        x: prev.x + dx,
        y: prev.y + dy,
      }));
      setStartPos({ x: e.clientX, y: e.clientY });
    }
  }, [dragging, startPos]);

  const handleMouseUp = useCallback(() => {
    setDragging(false);
  }, []);

  const handleWheel = useCallback((e) => {
    e.preventDefault();
    const zoomIntensity = 0.1;
    const newScale = e.deltaY < 0 ? scale + zoomIntensity : scale - zoomIntensity;
    setScale(Math.min(3, Math.max(0.5, newScale)));

    const rect = e.currentTarget.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    const mouseY = e.clientY - rect.top;
    setTransformOrigin(`${mouseX}px ${mouseY}px`);
  }, [scale]);

  return (
    <div
      onMouseDown={handleMouseDown}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
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
          transform: `translate(${offset.x}px, ${offset.y}px)`,
        }}
      >
        <div
          style={{
            transform: `scale(${scale})`,
            transformOrigin: transformOrigin,
            transition: 'transform 0.1s ease',
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
    </div>
  );
};

export default HexMap;
