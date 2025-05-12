import { StoreApi } from 'zustand';
import { GameStore } from '../../stores/gameStore';

export class GameLoop {
  private store: StoreApi<GameStore>;
  private animationFrameId: number | null = null;
  private lastTime: number = 0;

  constructor(store: StoreApi<GameStore>) {
    this.store = store;
  }

  public start() {
    this.lastTime = performance.now();
    this.animationFrameId = requestAnimationFrame(this.loop);
  }

  public stop() {
    if (this.animationFrameId !== null) {
      cancelAnimationFrame(this.animationFrameId);
      this.animationFrameId = null;
    }
  }

  private loop = (currentTime: number) => {
    const deltaTime = (currentTime - this.lastTime) / 1000; // seconds
    this.lastTime = currentTime;

    this.update(deltaTime);
    this.animationFrameId = requestAnimationFrame(this.loop);
  };


  private update(deltaTime: number) {
    const state = this.store.getState();
    
    // game logic here

  }
}
