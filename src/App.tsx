import MainGameScene from './game/scenes/mainGame';
import { SpeedInsights } from '@vercel/speed-insights/react';

const App = () => {
  return (
    <div>
      < MainGameScene />
      < SpeedInsights />
    </div>
  );
};

export default App;