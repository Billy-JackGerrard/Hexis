import { GameState } from "../../states/gameState";

interface Loop {
  state: GameState,
}
export class GameLoop implements Loop{

    public state : GameState;
    private lastTime: number = 0;
    private animationFrameId: number | null = null;

    constructor(state: GameState) {
      this.state = state
    }

    private loop = (time: number) => {
      const deltaTime = time - this.lastTime;
      this.lastTime = time;

      this.update(deltaTime);
      this.animationFrameId = requestAnimationFrame(this.loop);
    };

    start() {
      // initialise
      this.lastTime = performance.now();

      // start the actual loop
      this.animationFrameId = requestAnimationFrame(this.loop);
    }

    stop() {
      if (this.animationFrameId !== null) {
        cancelAnimationFrame(this.animationFrameId);
        this.animationFrameId = null;
      }
    }

    private update(deltaTime: number) {

    }
  }