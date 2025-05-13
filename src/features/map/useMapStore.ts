import { create } from 'zustand';

interface MapState {
  hexes: [];
}

export const useMapStore = create<MapState>((set) => ({
  hexes: []
}));