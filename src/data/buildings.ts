import { BuildingType, BuildingMetadata } from '../types';

export const BUILDINGS_METADATA: Record<BuildingType, BuildingMetadata> = {

    "empty": {
      displayName: "Empty",
      description: "An empty construction site",
      maxLevel: 0,
      palaceLevelRequired: 0,
      allowedTerrain: ["grassland", "desert", "hill", "mountain", "water"],
      baseHealth: 0,
      healthPerLevel: 0,
      buildCost: {},
      upgradeCostMultiplier: 0
    },
    "palace": {
      displayName: "Royal Palace",
      description: "The heart of your civilization. If destroyed, you lose the game. Unlocks new buildings.",
      maxLevel: 5,
      palaceLevelRequired: 0,
      allowedTerrain: ["grassland", "hill"],
      baseHealth: 500,
      healthPerLevel: 1000,
      buildCost: {"food": 50, "gold": 15},
      upgradeCostMultiplier: 3,
    },
    "headquarters": {
      displayName: "Headquarters",
      description: "Central command of a base. Limits maximum level of other buildings.",
      maxLevel: 5,
      palaceLevelRequired: 0,
      allowedTerrain: ["grassland", "desert", "hill"],
      baseHealth: 500,
      healthPerLevel: 200,
      buildCost: { "food": 100, "gold": 10 },
      upgradeCostMultiplier: 1.8,
    },
    "farm": {
      displayName: "Farm",
      description: "Produces food. Can be land animals, agriculture or a fish farm. More efficient near water.",
      maxLevel: 5,
      palaceLevelRequired: 1,
      allowedTerrain: ["grassland", "water"],
      baseHealth: 150,
      healthPerLevel: 30,
      buildCost: { "wood": 40 },
      upgradeCostMultiplier: 1.4,
      production: {
        resource: "food",
        baseRate: 15,
        ratePerLevel: 5,
        "adjacencyBonus": [{
          "type": "water",
          "bonus": 1.5
        }]
      },
    },
    "sawmill": {
        displayName: "Sawmill",
        description: "Extracts wood. Not very productive unless near a forest.",
        maxLevel: 5,
        palaceLevelRequired: 1,
        allowedTerrain: ["grassland", "forest"],
        baseHealth: 180,
        healthPerLevel: 30,
        buildCost: { "iron": 15, "food": 30},
        upgradeCostMultiplier: 1.7,
        production: {
            resource: "wood",
            baseRate: 10,
            ratePerLevel: 5,
            adjacencyBonus: [{
              "type": "forest",
              "bonus": 5
            }] 
          },
    },
    "mine": {
      displayName: "Iron Mine",
      description: "Extracts iron ore. More productive near mountains and hills.",
      maxLevel: 5,
      palaceLevelRequired: 1,
      allowedTerrain: ["grassland", "hill", "mountain"],
      baseHealth: 200,
      healthPerLevel: 30,
      buildCost: { "wood": 50, "food": 20},
      upgradeCostMultiplier: 1.5,
      production: {
        resource: "iron",
        baseRate: 6,
        "ratePerLevel": 4,
        adjacencyBonus: [{
          "type": "mountain",
          "bonus": 1.8
        },{
            "type": "hill",
            "bonus": 1.2
        }]  
      }
    },
    "windmill": {
      displayName: "Windmill",
      description: "Generates clean energy. More productive near hills and on windy days.",
      maxLevel: 3,
      palaceLevelRequired: 2,
      allowedTerrain: ["grassland", "hill"],
      baseHealth: 120,
      healthPerLevel: 20,
      buildCost: { "wood": 80, "iron": 20 },
      upgradeCostMultiplier: 1.6,
      production: {
        resource: "energy",
        baseRate: 15,
        ratePerLevel: 6,
        adjacencyBonus: [{
          "type": "hill",
          "bonus": 1.4
      }]
      },
    },
    "house": {
      displayName: "Housing",
      description: "Increases population capacity. Requires food to sustain.",
      maxLevel: 1,
      palaceLevelRequired: 1,
      allowedTerrain: ["grassland", "desert", "hill"],
      baseHealth: 100,
      healthPerLevel: 20,
      buildCost: { "wood": 40, "food": 50 },
      upgradeCostMultiplier: 1.2
    },
    "turret": {
      displayName: "Gun Turret",
      description: "Basic defensive structure with rapid fire bullets.",
      maxLevel: 6,
      palaceLevelRequired: 3,
      allowedTerrain: ["grassland", "desert", "hill"],
      baseHealth: 300,
      healthPerLevel: 50,
      buildCost: { "iron": 80 },
      upgradeCostMultiplier: 1.6,
      attack: {
        baseDamage: 20,
        damagePerLevel: 10,
        baseRange: 3,
        rangePerLevel: 0.1,
        reloadTime: 1,
        isAOE: false
      }
    },
    "missile": {
      displayName: "Missile Silo",
      description: "Advanced defence with long range and area of effect explosions.",
      maxLevel: 3,
      palaceLevelRequired: 4,
      allowedTerrain: ["grassland", "desert", "hill"],
      baseHealth: 300,
      healthPerLevel: 50,
      buildCost: { "iron": 120 },
      upgradeCostMultiplier: 2.0,
      attack: {
        baseDamage: 50,
        damagePerLevel: 25,
        baseRange: 5,
        rangePerLevel: 0.5,
        reloadTime: 4,
        isAOE: true
      },
    },
    "barracks": {
        displayName: "Infantry Barracks",
        description: "Trains infantry troops.",
        maxLevel: 3,
        palaceLevelRequired: 2,
        allowedTerrain: ["grassland", "desert"],
        baseHealth: 200,
        healthPerLevel: 50,
        buildCost: { "wood": 40, "food": 50},
        upgradeCostMultiplier: 1.6,
      },
    "factory": {
      displayName: "Vehicle Factory",
      description: "Produces land vehicles.",
      maxLevel: 3,
      palaceLevelRequired: 3,
      allowedTerrain: ["grassland", "desert"],
      baseHealth: 300,
      healthPerLevel: 80,
      buildCost: { "iron": 40, "energy": 100},
      upgradeCostMultiplier: 1.8,
    }
}