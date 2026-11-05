#!/bin/zsh
# Usage: make-svg.sh glow|plain [bleed|tile] > out.svg
# bleed (default) fills the whole canvas with no shape of its own, so macOS 26 applies its
# system mask instead of shrinking the icon onto a plain plate. tile draws the rounded tile,
# rim and shadow itself, for places that show the artwork unmasked.
VARIANT=${1:-glow}
SHAPE=${2:-bleed}
RX=185 SCALE_OPEN="" SCALE_CLOSE=""
SHADOW='  <rect x="100" y="112" width="824" height="824" rx="185" fill="#000" opacity="0.45" filter="url(#drop)" mask="url(#outsideTile)"/>'
RIMS='  <rect x="102" y="102" width="820" height="820" rx="183" fill="none" stroke="url(#rim)" stroke-width="4"/>
  <rect x="108" y="108" width="808" height="808" rx="177" fill="none" stroke="#000" stroke-opacity="0.35" stroke-width="3"/>'
if [[ $SHAPE == bleed ]]; then
    # macOS only masks a legacy icon it reads as a full square, so the body is opaque here.
    RX=0 SHADOW="" RIMS="" BODY_ALPHA=1
    # Scale the 824pt tile up to the full 1024 canvas so the folder keeps its proportion.
    SCALE_OPEN='<g transform="translate(512 512) scale(1.242718) translate(-512 -512)">' SCALE_CLOSE='</g>'
fi
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
    <clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="${RX}"/></clipPath>
    <mask id="outsideTile"><rect width="1024" height="1024" fill="#fff"/><rect x="100" y="100" width="824" height="824" rx="185" fill="#000"/></mask>
    <clipPath id="back"><path d="M291 300H428Q452 300 467 318L485 340H733Q777 340 777 384V680Q777 724 733 724H291Q247 724 247 680V344Q247 300 291 300Z"/></clipPath>
    <!-- Smoky glass body: dark, faintly blue, still slightly see-through -->
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1e2331" stop-opacity="${BODY_ALPHA:-0.93}"/>
      <stop offset="0.55" stop-color="#11141c" stop-opacity="${BODY_ALPHA:-0.94}"/>
      <stop offset="1" stop-color="#05060a" stop-opacity="${BODY_ALPHA:-0.96}"/>
    </linearGradient>
    <!-- Light gathering inside the lower edge, as it does in thick glass -->
    <radialGradient id="caustic" cx="0.5" cy="1.02" r="0.62">
      <stop offset="0" stop-color="#9fb4ff" stop-opacity="0.30"/>
      <stop offset="0.45" stop-color="#6f86d8" stop-opacity="0.10"/>
      <stop offset="1" stop-color="#6f86d8" stop-opacity="0"/>
    </radialGradient>
    <!-- Curved reflection across the top -->
    <linearGradient id="reflection" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff" stop-opacity="0.17"/>
      <stop offset="0.55" stop-color="#fff" stop-opacity="0.04"/>
      <stop offset="1" stop-color="#fff" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff" stop-opacity="0.75"/>
      <stop offset="0.3" stop-color="#fff" stop-opacity="0.16"/>
      <stop offset="0.7" stop-color="#fff" stop-opacity="0.06"/>
      <stop offset="1" stop-color="#fff" stop-opacity="0.38"/>
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

  ${SCALE_OPEN}
  <!-- tile shadow -->
${SHADOW}
  <!-- tile -->
  <rect x="100" y="100" width="824" height="824" rx="${RX}" fill="url(#bg)"/>${GLOW}
  <g clip-path="url(#tile)">
    <rect x="100" y="100" width="824" height="824" fill="url(#caustic)"/>
    <path d="M100 100H924V420C760 470 600 360 100 470Z" fill="url(#reflection)"/>
  </g>
  <!-- glass edge: bright outer rim, thin dark line inside it for thickness -->
${RIMS}

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
  ${SCALE_CLOSE}
</svg>
SVG
