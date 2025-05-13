import { useMapStore } from './useMapStore';

export function createMap() {
  const { hexes } = useMapStore();
  
  return (
    <Stage>
      {hexes.map(hex => (
        <HexGraphics key={`${hex.q}-${hex.r}`} hex={hex} />
      ))}
    </Stage>
  );
}