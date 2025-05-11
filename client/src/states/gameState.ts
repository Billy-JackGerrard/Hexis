import { create } from 'zustand';
import { Hex, calcKey } from "../types";

export interface GameState {
  grid: Readonly<Record<string, Readonly<Hex>>>;
  updateHex: (key: string, updates: Partial<Omit<Hex, 'coords'>>) => void;
}

export const createGameState = (initialHexes: Hex[]) => 
  
  create<GameState>((set) => ({
    grid: initialHexes.reduce((acc, hex) => ({
      ...acc,
      [calcKey(hex.coords)]: hex
    }), {}),
    
    updateHex: (key, updates) => set((state) => {
      if (!state.grid[key]) return state;
      return { grid: { ...state.grid, [key]: { ...state.grid[key], ...updates } } };
    })
  }));