// This file is gunna be big. Might be worth splitting it up into multiple files later.
import * as PIXI from 'pixi.js';
import { Viewport } from 'pixi-viewport';
import * as honeycomb from 'honeycomb-grid';
import { Hex } from '../game-mechanics/hex/types';

export default async function renderMap(container: HTMLElement) {

    // Initialize PixiJS application (correct for v8) and add it to the DOM
    const app = new PIXI.Application();
    await app.init({
        resizeTo: window,
        backgroundColor: 0x233345, // blue background
        antialias: true,
        resolution: window.devicePixelRatio || 1,
    });
    container.appendChild(app.canvas);

    // Create viewport for scrolling/zooming
    const viewport = new Viewport({
        events: app.renderer.events,
        screenWidth: app.screen.width,
        screenHeight: app.screen.height,
        worldWidth: 5000,
        worldHeight: 5000,
    });
    app.stage.addChild(viewport);
    viewport.drag().pinch().wheel().decelerate();

    

    // Create grid
    const grid = new honeycomb.Grid(
        // defining the hexagon type and size
        honeycomb.defineHex({
            dimensions: 30,
            orientation: honeycomb.Orientation.POINTY,
            origin: { x: 0, y: 0 }
        }),
        // defining the grid shape and size
        honeycomb.rectangle({
            width: 10,
            height: 10 }))



    // Create hex graphics
    const graphics = new PIXI.Graphics();
    viewport.addChild(graphics);
    graphics.stroke({ width: 1, color: 0xFFFFFF });

    grid.forEach((h) => {

        const corners = h.corners.map(corner => ({
            x: corner.x + h.x,
            y: corner.y + h.y
        }));

        graphics.fill({color: 0x233345, alpha: 1});
        graphics.poly(corners);
    });



    // Center viewport on the hex grid
    viewport.fit();
    const centerHex = grid.getHex([0 , 0]); // change this to the hex of the HQ of the player's home base
    if (!centerHex) throw new Error('Center hex not found');
    viewport.moveCenter(centerHex.x, centerHex.y);

    return 
    
}