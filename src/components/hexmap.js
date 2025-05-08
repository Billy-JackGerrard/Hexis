
import React from 'react';
import { HexGrid, Layout, Hexagon } from 'react-hexgrid';

const HexMap = () => {
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

  return (
    <div style={{ overflow: 'scroll', width: '100vw', height: '100vh' }}>
      <HexGrid width={2000} height={2000}>
        <Layout size={{ x: 5, y: 5 }} flat={false} spacing={1.1} origin={{ x: 0, y: 0 }}>
          {hexagons.map(({ q, r, s }, i) => (
            <Hexagon key={i} q={q} r={r} s={s} />
          ))}
        </Layout>
      </HexGrid>
    </div>
  );
};

export default HexMap;
