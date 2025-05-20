
import Phaser from 'phaser';

// Initialize Phaser game

export const game = new Phaser.Game({
    type: Phaser.AUTO,
    parent: 'game-container', // Matches the div ID below
    width: 800,
    height: 600,
    scene: {
      preload: preload,
      create: create
  }
});

function preload() {
  // We'll load assets here
}

function create() {
  // We'll create our hex map here
}