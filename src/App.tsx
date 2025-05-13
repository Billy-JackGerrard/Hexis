import MainGameScene from './scenes/mainGame';
import { SpeedInsights } from '@vercel/speed-insights/react';

const App = () => {
  return (
    <div className="game-container">
      < MainGameScene />
      < SpeedInsights />
    </div>
  );
};

export default App;