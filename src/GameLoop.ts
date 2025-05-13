

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

    // game logic here

  }
}