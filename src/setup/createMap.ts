// This file is gunna be big. Might be worth splitting it up into multiple files/functions later.
import * as PIXI from 'pixi.js';
import { Viewport } from 'pixi-viewport';
import * as honeycomb from 'honeycomb-grid';



const HEXAGON_SIZE = 30; // Size of each hexagon
const HEXAGON_QUANTITY = 10; // Number of hexagons in each direction



export default async function createMap(container: HTMLElement) {
    
    // container.innerHTML = ''; // Clear the container before adding the map

    // Initialise PixiJS application (correct for v8) and add it to the DOM
    const app = new PIXI.Application();
    await app.init({
        resizeTo: window,
        backgroundColor: 0x1580ea, // blue background
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

    
    const padding = HEXAGON_SIZE * 2;

    // assigning bounds
    const bounds = {
        left: minX,
        right: maxX,
        top: minY,
        bottom: maxY,
        width: maxX - minX,
        height: maxY - minY
    };
    
    // create viewport, ie what the user sees
    const viewport = new Viewport({
        events: app.renderer.events,
        screenWidth: app.screen.width,
        screenHeight: app.screen.height,
        worldWidth: bounds.width + padding * 4,
        worldHeight: bounds.height + padding * 4,
    });

    // Set hard boundaries
    viewport.clamp({
        left: bounds.left - padding,
        right: bounds.right + padding,
        top: bounds.top - padding,
        bottom: bounds.bottom + padding
    });

    // Center viewport
    viewport.moveCenter(
        bounds.left + bounds.width/2,
        bounds.top + bounds.height/2
    );


    // debugging
    console.log({
        containerClient: { width: container.clientWidth, height: container.clientHeight },
        containerOffset: { width: container.offsetWidth, height: container.offsetHeight },
        containerScroll: { width: container.scrollWidth, height: container.scrollHeight },
        appCanvas: { width: app.canvas.height, height: app.canvas.clientHeight },
        window: { innerWidth: window.innerWidth, innerHeight: window.innerHeight },
        screen: { width: app.screen.width, height: app.screen.height },
        renderer: { width: app.renderer.width, height: app.renderer.height },
        parentItem: document.getElementById('root')?.parentElement,
        devicePixelRatio: window.devicePixelRatio
    });
    console.log('Viewport world size:', viewport.worldWidth, viewport.worldHeight);
    console.log('Grid bounds:', bounds);

    


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

// Replace with terrain images etc
function getHexColor(hex: honeycomb.Hex): number {
    // Add your biome/terrain logic here
    return 0x90EE90; // Light green
}