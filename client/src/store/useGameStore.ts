import { create } from 'zustand';
import { Hex, calcKey } from "../types";

interface GameState {
  grid: Record<string, Hex>;
  addHex: (hex: Hex) => void;
}

export const useGameStore = create<GameState>((set) => ({
  grid: {},
  
  addHex: (hex: Hex) => set((state) => ({
    grid: { 
      ...state.grid, 
      [calcKey(hex.coords)]: hex
    }
  })),
  
}));