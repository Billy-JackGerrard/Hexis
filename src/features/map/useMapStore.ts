import { create } from 'zustand';

interface MapState {
  hexes: Hex[];
}

export const useMapStore = create<MapState>((set) => ({
  hexes: []
}));