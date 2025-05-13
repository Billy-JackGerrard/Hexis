// src/engine/rendering/initializePixi.ts
import * as PIXI from 'pixi.js'

export function initializePixi(container: HTMLDivElement): PIXI.Application {
  const app = new PIXI.Application({
    resizeTo: window,
    backgroundColor: 0x000000, // or your map background color
    antialias: true,
  })

  container.appendChild(app.view as HTMLCanvasElement)

  return app
}
