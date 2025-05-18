// This file is gunna be big. Might be worth splitting it up into multiple files/functions later.
import * as PIXI from 'pixi.js';
import { Viewport } from 'pixi-viewport';
import createGrid from './createGrid';
import { HEXAGON_SIZE } from '../data/config';
import { Terrain } from '../data/types';



export default async function renderMap(container: HTMLElement) {
    
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
            

    // get grid
    const grid = createGrid();


    // for calculating bounds
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;

    // go through each hexagon in the grid
    grid.forEach(hex => {
        
        // Draw hex
        graphics.fill({ color: getColour(hex.terrain), alpha: 1 });
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
        viewportWorld: { width: viewport.worldWidth, height: viewport.worldHeight },
        parentItem: document.getElementById('root')?.parentElement,
        devicePixelRatio: window.devicePixelRatio
    });
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
function getColour(terrain: Terrain): number {
    
    switch (terrain) {
        case 'grass':
            return 0x00FF00; // Green
        case 'mountain':
            return 0xA9A9A9; // Grey
        default:
            return 0xFFFFFF; // White
    }
    
    // return 0x90EE90; // Light green
}