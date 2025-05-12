import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,  // Set your preferred port
    open: true   // Automatically open browser
  },
  build: {
    outDir: 'build',  // Output folder for build
    emptyOutDir: true
  }
})