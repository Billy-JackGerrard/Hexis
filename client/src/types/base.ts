import { BuildingType } from './building';

export interface Base {
    baseId: string,
    playerId: string,
    homeBase: boolean,
    
    buildingsBuilt: BuildingType[],
}