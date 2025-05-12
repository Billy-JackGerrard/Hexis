import { useGameStore } from '../../stores/gameStore';

export class GameLoop {
  private animationFrameId: number | null = null;
  private lastTime: number = 0;

  constructor() {}

  public start() {
    this.lastTime = performance.now();
    this.animationFrameId = requestAnimationFrame(this.loop);
  }

  public stop() {
    if (this.animationFrameId !== null) {
      cancelAnimationFrame(this.animationFrameId);
      this.animationFrameId = null;
      this.lastTime = 0;
    }
  }

  private loop = (currentTime: number) => {
    const deltaTime = (currentTime - this.lastTime) / 1000; // seconds
    this.lastTime = currentTime;

    this.update(deltaTime);
    this.animationFrameId = requestAnimationFrame(this.loop);
  };


  private update(deltaTime: number) {
    
    // TODO: change this to be a selector, to reduce re-renders. the actual selector depends on the game logic implemented below
    // const hex = useGameStore(state => state.grid[calcKey(coords)]);



    // TODO: game logic here

  }
}