import { BuildingType } from "./building";
import { Resource } from "./resource";


export interface PlayerInterface {
    userId: string,
    buildingsUnlocked: BuildingType[],
    resources: {
        [key in Resource]: number
    }
}