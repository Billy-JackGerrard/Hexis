import { Player, Resource, BuildingType, TroopType, BUILDINGS_METADATA } from '../../types';


export class PlayerEntity implements Player {
    
    public readonly resources: Record<Resource, number> = {
        wood: 50,
        food: 50,
        iron: 20,
        energy: 0,
        gold: 50,
      };
    public bases: string[] = []; // Array of base IDs
    public palaceLevel: number = 0;
    public lastCollectionTime: number = Date.now();
    
    constructor(
      public readonly id: string,
      public username: string,
      private homeBaseId: string,
    ) {
        this.bases.push(homeBaseId);
    }

    unlockedBuildings() : BuildingType[] {
        const buildings: BuildingType[] = [];

        for ( const building of Object.keys(BUILDINGS_METADATA) as BuildingType[] ) {

            if ( this.palaceLevel >= BUILDINGS_METADATA[building].palaceLevelRequired ) {
                buildings.push(building);
            }
        }
        return buildings;
    }

    // TODO
    unlockedTroops() : TroopType[] {
        return ['Jeep'];
    }


    gainResource( resource: Resource, quantity: number) {
        this.resources[resource] += quantity;
    }

    loseResource( resource: Resource, quantity: number) {
        this.resources[resource] -= quantity;
    }

}