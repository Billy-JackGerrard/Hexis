// Define a type for a hex


// types/game.ts
export enum HexType {
  LAND = 'land',
  BASE = 'base',
  OBSTACLE = 'obstacle'
}

export interface HexCoordinates {
  q: number;
  r: number;
  s: number;
}

export interface HexResources {
  wood: number;
  stone: number;
  water: number;
  food: number;
}

export interface Hex {
  coords: HexCoordinates;
  type: HexType;
  resources: HexResources;
  colour: string;
}



export interface Hex {
  coords: HexCoordinates;
  type: HexType;
  resources: HexResources;
  colour: string;
  // Add any other fields you need (e.g., `terrain` if necessary)
}
  
  
  
// Define the game state
  export interface GameState {
    hexagons: Record<string, Hex>;
    setGameState: (state: Partial<GameState>) => void;
  }