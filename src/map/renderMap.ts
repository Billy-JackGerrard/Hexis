
import * as PIXI from 'pixi.js';
import { Viewport } from 'pixi-viewport';
import createGrid from './createGrid';
import { HEXAGON_SIZE, BACKGROUND_COLOUR } from '../data/config';
import { Terrain } from '../data/types';



export default async function renderMap(container: HTMLElement) {
    
    // container.innerHTML = ''; // Clear the container before adding the map

    // Initialise PixiJS application (correct for v8) and add it to the DOM
    const app = new PIXI.Application();
    await app.init({
        resizeTo: window,
        backgroundColor: BACKGROUND_COLOUR, // blue background
        antialias: true,
        resolution: window.devicePixelRatio || 1,
    });
    container.appendChild(app.canvas);


    // for rendering
    const mapContainer = new PIXI.Container();

    // get grid
    const grid = createGrid();


    // for calculating bounds
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;

    // go through each hexagon in the grid
    grid.forEach(hex => {

        
        // draw hexagon
        const g = new PIXI.Graphics();
        g.fill({ color: getColour(hex.terrain) });
        g.poly(hex.corners);
        g.stroke({ width: 1, color: 0xFFFFFF });
        g.eventMode = 'static';
        g.cursor = 'pointer';

        // add interactivity
        g.on('pointerdown', () => {
            console.log('Clicked hex:', hex.q, hex.r, hex.s, hex.terrain);
        });

        mapContainer.addChild(g);
                

        // update bounds
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
    viewport.addChild(mapContainer);

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
        case 'forest':
            return 0x228B22; // Forest Green
        case 'hill':
            return 0x8B4513; // Saddle Brown
        case 'desert':
            return 0xFFD700; // Gold
        case 'water':
            return 0x0000FF; // Blue
        case 'mountain':
            return 0xA9A9A9; // Grey
        default:
            return 0xFFFFFF; // White
    }
    
}