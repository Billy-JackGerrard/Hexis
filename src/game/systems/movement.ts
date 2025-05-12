import { Terrain } from "../../types";

function isTraversable(terrain: Terrain): boolean {
    return ["grassland"].includes(terrain);
  }