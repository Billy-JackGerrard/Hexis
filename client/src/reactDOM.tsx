import ReactDOM from 'react-dom/client';
import App from './App';
import './index.css'; // Global styles

// Create the root element and render the App component inside it
const root = ReactDOM.createRoot(document.getElementById('root') as HTMLElement);
root.render(<App />);