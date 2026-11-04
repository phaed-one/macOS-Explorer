#!/bin/zsh
# Usage: make-svg.sh glow|plain > out.svg
VARIANT=${1:-glow}
GLOW=""
if [[ $VARIANT == glow ]]; then
GLOW='
    <g clip-path="url(#tile)" filter="url(#soft)" opacity="0.32">
      <circle cx="230" cy="880" r="240" fill="#2a5cff"/>
      <circle cx="820" cy="840" r="220" fill="#ff2d87"/>
      <circle cx="520" cy="900" r="160" fill="#8b3dff"/>
    </g>'
fi
cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
    <clipPath id="back"><path d="M291 300H428Q452 300 467 318L485 340H733Q777 340 777 384V680Q777 724 733 724H291Q247 724 247 680V344Q247 300 291 300Z"/></clipPath>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1b1b24"/>
      <stop offset="1" stop-color="#030305"/>
    </linearGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff" stop-opacity="0.22"/>
      <stop offset="0.5" stop-color="#fff" stop-opacity="0.05"/>
      <stop offset="1" stop-color="#fff" stop-opacity="0.12"/>
    </linearGradient>
    <linearGradient id="backFill" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#e4e6ee"/>
      <stop offset="1" stop-color="#b9bcc8"/>
    </linearGradient>
    <linearGradient id="frontFill" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff"/>
      <stop offset="1" stop-color="#e9ebf2"/>
    </linearGradient>
    <filter id="drop" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="14"/>
    </filter>
    <filter id="soft" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="90"/>
    </filter>
    <filter id="lip" x="-10%" y="-30%" width="120%" height="160%">
      <feGaussianBlur stdDeviation="10"/>
    </filter>
  </defs>

  <!-- tile shadow -->
  <rect x="100" y="112" width="824" height="824" rx="185" fill="#000" opacity="0.45" filter="url(#drop)"/>
  <!-- tile -->
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>${GLOW}
  <rect x="101.5" y="101.5" width="821" height="821" rx="183.5" fill="none" stroke="url(#rim)" stroke-width="3"/>

  <!-- folder shadow -->
  <rect x="257" y="330" width="510" height="410" rx="44" fill="#000" opacity="0.5" filter="url(#drop)"/>
  <!-- folder back -->
  <path d="M291 300H428Q452 300 467 318L485 340H733Q777 340 777 384V680Q777 724 733 724H291Q247 724 247 680V344Q247 300 291 300Z" fill="url(#backFill)"/>
  <!-- shadow the front casts on the back -->
  <g clip-path="url(#back)">
    <rect x="247" y="392" width="530" height="332" rx="44" fill="#000" opacity="0.28" filter="url(#lip)"/>
  </g>
  <!-- folder front -->
  <rect x="247" y="404" width="530" height="320" rx="44" fill="url(#frontFill)"/>
  <rect x="248.5" y="405.5" width="527" height="317" rx="42.5" fill="none" stroke="#fff" stroke-width="3" opacity="0.9"/>
</svg>
SVG
