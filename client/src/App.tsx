import { MainGameScene } from './game/scenes/mainGame';
import { SpeedInsights } from '@vercel/speed-insights/react';

const App = () => {
  return (
    <div>
      <h1>Hex Game</h1>
      < MainGameScene />
    </div>
  );
};

export default App;