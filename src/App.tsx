import { MainGameScene } from './game/scenes/mainGame';
import { SpeedInsights } from '@vercel/speed-insights/react';

const App = () => {
  return (
    <div>
      <h1>Stupid Game</h1>
      < MainGameScene />
      < SpeedInsights />
    </div>
  );
};

export default App;