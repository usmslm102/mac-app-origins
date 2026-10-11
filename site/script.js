const toggle = document.querySelector('#demo-toggle');
const demo = document.querySelector('#demo-image');
const label = document.querySelector('#play-label');
const symbol = document.querySelector('#play-symbol');
const status = document.querySelector('#demo-status');
const player = document.querySelector('.demo-player');
let playing = false;

// The GIF is loaded only on request, including for reduced-motion users.
toggle.hidden = false;
toggle.addEventListener('click', () => {
  playing = !playing;
  demo.src = playing ? 'assets/demo.gif' : 'assets/screenshot.png';
  demo.alt = playing ? 'Animated walkthrough of AppOrigins scanning and inspecting installed software' : 'AppOrigins demo preview';
  player.classList.toggle('is-playing', playing);
  label.textContent = playing ? 'Stop demo' : 'Play demo';
  symbol.textContent = playing ? '■' : '▶';
  status.textContent = playing ? 'Demo playing. Select Stop demo to return to the still preview.' : 'Scan. Filter. Inspect. Everything in one native window.';
});
demo.addEventListener('error', () => {
  if (playing) {
    toggle.click();
    status.textContent = 'The demo could not load. Please try again.';
  }
});
