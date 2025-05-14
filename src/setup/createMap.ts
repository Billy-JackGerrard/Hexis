// This file is gunna be big. Might be worth splitting it up into multiple files later.
import * as PIXI from 'pixi.js';
import { Viewport } from 'pixi-viewport';
import * as honeycomb from 'honeycomb-grid';



const HEXAGON_SIZE = 30; // Size of each hexagon
const HEXAGON_QUANTITY = 40; // Number of hexagons in each direction



export default async function createMap(container: HTMLElement) {
    
    container.innerHTML = ''; // Clear the container before adding the map

    // Initialize PixiJS application (correct for v8) and add it to the DOM
    const app = new PIXI.Application();
    await app.init({
        resizeTo: window,
        backgroundColor: 0x233345, // blue background
        antialias: true,
        resolution: window.devicePixelRatio || 1,
    });
    container.appendChild(app.canvas);


    // for rendering
    const graphics = new PIXI.Graphics();

    // Create grid
    const grid = new honeycomb.Grid(
        // defining the hexagon type and size
        honeycomb.defineHex({
            dimensions: HEXAGON_SIZE,
            orientation: honeycomb.Orientation.POINTY,
            origin: { x: 0, y: 0 }
        }),
        // defining the grid shape and size
        honeycomb.rectangle({
            width: HEXAGON_QUANTITY,
            height: HEXAGON_QUANTITY,
        }))
            


    // for calculating bounds
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;

    // go through each hexagon in the grid
    grid.forEach(hex => {
        
        // Draw hex
        graphics.fill({ color: getHexColor(hex), alpha: 1 });
        graphics.poly(hex.corners);
        graphics.stroke({ width: 1, color: 0xFFFFFF });

        // Update bounds
        hex.corners.forEach(corner => {
            minX = Math.min(minX, corner.x);
            minY = Math.min(minY, corner.y);
            maxX = Math.max(maxX, corner.x);
            maxY = Math.max(maxY, corner.y);
        });
    });

    // assigning bounds
    const bounds = {
        left: minX,
        right: maxX,
        top: minY,
        bottom: maxY,
        width: maxX - minX,
        height: maxY - minY
    };
    const padding = 0;// HEXAGON_SIZE * 2;
    
    // create viewport, ie what the user sees
    const viewport = new Viewport({
        events: app.renderer.events,
        screenWidth: app.screen.width,
        screenHeight: app.screen.height,
        worldWidth: bounds.width + padding * 2,
        worldHeight: bounds.height + padding * 2,
    });

    // Set hard boundaries
    viewport.clamp({
        left: bounds.left - padding/2,
        right: bounds.right + padding/2,
        top: bounds.top - padding/2,
        bottom: bounds.bottom + padding/2
    });

    // Center viewport
    viewport.moveCenter(
        bounds.left + bounds.width/2,
        bounds.top + bounds.height/2
    );


    // debugging

    console.log('Viewport world size:', viewport.worldWidth, viewport.worldHeight);
    console.log('Viewport center:', viewport.center);

    console.log('Grid bounds:', bounds);
    console.log('Grid size:', grid.size);
    


    app.stage.addChild(viewport);
    viewport.drag().pinch().decelerate(); // .wheel()
    viewport.addChild(graphics);

    return {
        destroy: () => {
            app.destroy(true, { children: true });
            container.innerHTML = ''
        }
    }
    
}





function renderMap(viewport: Viewport, grid: honeycomb.Grid<honeycomb.Hex>): void {
    const graphics = new PIXI.Graphics();
    viewport.addChild(graphics);
    
    graphics.stroke({ // this is what's in between the hexes
        width: 0,
        color: 0xFFFFFF,
        alpha: 1 // transparency
    });
    
    grid.forEach((hex) => {
        const corners = hex.corners.map(corner => ({
            x: corner.x + hex.x,
            y: corner.y + hex.y
        }));

        // Basic styling - consider making this configurable
        graphics.fill({ color: getHexColor(hex), alpha: 1 });
        graphics.poly(corners);
    });
}


// Replace with terrain images etc
function getHexColor(hex: honeycomb.Hex): number {
    // Add your biome/terrain logic here
    return 0x90EE90; // Light green
}