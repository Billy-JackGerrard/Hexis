import { create } from 'zustand';
import { GameState } from "../types"

export const useGameStore = create<GameState>((set) => ({
  // Initial state
  hexagons: {},
  
  // Action to update state
  setGameState: (state) => set((prevState) => ({ ...prevState, ...state })),
}));