
export type TroopType =
    | 'Jeep'
    ;

export interface Troop {
    id: string;
    type: TroopType;
    level: number;
    currentHealth: number;
}