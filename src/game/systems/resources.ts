import { Base, Player, Resource } from "../../types";
import { useStore } from 'zustand';
import { gameStore } from "../../stores/gameStore";

function collectResources(player: Player) {

    // Get current time in milliseconds
    const currentTime = Date.now();

    // Calculate time passed in minutes
    const minutesPassed = (currentTime - player.lastCollectionTime) / 60000; 
    
    // get all bases of the player
    const bases = useStore(gameStore, (state) => state.bases);
    const totalProductionRate: Partial<Record<Resource, number>> = {};
    
    // Iterate through each base that belongs to the player and add up the production rates
    Object.values(bases).forEach((base: Base) => {

        // Check if the base belongs to the player
        if (base.playerId === player.id) {

            // Add production rates to totalProductionRate
            for (const [resource, rate] of Object.entries(base.productionRates) as [Resource, number][]) {
                totalProductionRate[resource] = (totalProductionRate[resource] || 0) + rate;
            }
        }
    });


    // Add resources
    for (const [resource, rate] of Object.entries(totalProductionRate) as [Resource, number][]) {
      player.gainResource(resource, rate * minutesPassed);
    }
    
    // Update last collection time
    player.lastCollectionTime = currentTime;
  }