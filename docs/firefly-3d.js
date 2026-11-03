/**
 * Firefly 3D iPhone illustration — MIT licensed Three.js (0.186.1).
 * Procedural geometry, no downloaded models, fonts, trackers, or private data.
 * Progressive enhancement: existing CSS phone remains visible until WebGL renders.
 */
import * as THREE from 'https://cdn.jsdelivr.net/npm/three@0.186.1/build/three.module.js';

const mount = document.getElementById('firefly-three-mount');
const canvas = document.getElementById('firefly-three-canvas');
const wrapper = document.getElementById('firefly-phone-wrap');
const stage = document.getElementById('story-demo');
if (!mount || !canvas || !wrapper || !stage) {
  throw new Error('Firefly 3D demo mount not found.');
}

let renderer;
try {
  renderer = new THREE.WebGLRenderer({
    canvas: canvas,
    alpha: true,
    antialias: true,
    premultipliedAlpha: false,
    powerPreference: 'low-power'
  });
} catch (error) {
  console.warn('Firefly 3D is unavailable; keeping the accessible 2D fallback.', error);
}
if (renderer) {
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.23;
  renderer.setClearColor(0x000000, 0);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(36, 1, 0.1, 100);
  camera.position.set(0, -0.42, 10.4);
  camera.lookAt(0, -0.42, 0);

  scene.add(new THREE.HemisphereLight(0xe9f2ff, 0x47546d, 2.7));
  const key = new THREE.DirectionalLight(0xffffff, 3.3);
  key.position.set(-3.7, 6, 7);
  scene.add(key);
  const edgeLight = new THREE.DirectionalLight(0xa7bfff, 2.8);
  edgeLight.position.set(4, 2, -5);
  scene.add(edgeLight);
  const warmLight = new THREE.DirectionalLight(0xffd5a8, 1.2);
  warmLight.position.set(2, -3, 5);
  scene.add(warmLight);

  const handset = new THREE.Group();
  scene.add(handset);

  function roundedShape(width, height, radius) {
    const shape = new THREE.Shape();
    const left = -width / 2, bottom = -height / 2;
    shape.moveTo(left + radius, bottom);
    shape.lineTo(left + width - radius, bottom);
    shape.quadraticCurveTo(left + width, bottom, left + width, bottom + radius);
    shape.lineTo(left + width, bottom + height - radius);
    shape.quadraticCurveTo(left + width, bottom + height, left + width - radius, bottom + height);
    shape.lineTo(left + radius, bottom + height);
    shape.quadraticCurveTo(left, bottom + height, left, bottom + height - radius);
    shape.lineTo(left, bottom + radius);
    shape.quadraticCurveTo(left, bottom, left + radius, bottom);
    shape.closePath();
    return shape;
  }

  const metal = new THREE.MeshPhysicalMaterial({
    color: 0x586170,
    metalness: 0.84,
    roughness: 0.31,
    clearcoat: 0.52,
    clearcoatRoughness: 0.22
  });
  const graphite = new THREE.MeshStandardMaterial({color: 0x151920, metalness: 0.55, roughness: 0.34});
  const glass = new THREE.MeshPhysicalMaterial({color: 0x101521, metalness: 0.25, roughness: 0.14, clearcoat: 0.92});
  const lens = new THREE.MeshPhysicalMaterial({color: 0x111922, metalness: 0.44, roughness: 0.10, clearcoat: 0.92});

  const chassis = new THREE.ExtrudeGeometry(roundedShape(2.17, 4.41, 0.33), {
    steps: 1, depth: 0.20, bevelEnabled: true,
    bevelThickness: 0.045, bevelSize: 0.038,
    bevelSegments: 5, curveSegments: 16
  });
  chassis.translate(0, 0, -0.10);
  const frame = new THREE.Mesh(chassis, metal);
  handset.add(frame);

  const backShape = new THREE.ShapeGeometry(roundedShape(2.02, 4.26, 0.30), 14);
  const back = new THREE.Mesh(backShape, graphite);
  back.position.z = -0.17;
  back.rotation.y = Math.PI;
  handset.add(back);

  const screenGlass = new THREE.Mesh(new THREE.PlaneGeometry(2.08, 4.30), glass);
  screenGlass.position.z = 0.153;
  handset.add(screenGlass);

  const displayCanvas = document.createElement('canvas');
  displayCanvas.width = 540;
  displayCanvas.height = 1120;
  const context = displayCanvas.getContext('2d', {alpha: true});
  const displayTexture = new THREE.CanvasTexture(displayCanvas);
  displayTexture.colorSpace = THREE.SRGBColorSpace;
  displayTexture.anisotropy = Math.min(4, renderer.capabilities.getMaxAnisotropy());
  const displayMesh = new THREE.Mesh(
    new THREE.PlaneGeometry(2.025, 4.225),
    new THREE.MeshBasicMaterial({
      map: displayTexture,
      transparent: true,
      depthWrite: false,
      toneMapped: false
    })
  );
  displayMesh.position.z = 0.162;
  handset.add(displayMesh);

  // Side keys make the thin 3D silhouette readable in angled poses.
  const volume = new THREE.Mesh(new THREE.BoxGeometry(0.048, 0.50, 0.09), metal);
  volume.position.set(-1.127, 0.85, 0);
  handset.add(volume);
  const power = new THREE.Mesh(new THREE.BoxGeometry(0.048, 0.52, 0.09), metal);
  power.position.set(1.127, 0.52, 0);
  handset.add(power);

  const port = new THREE.Mesh(new THREE.BoxGeometry(0.31, 0.035, 0.10), graphite);
  port.position.set(0, -2.245, 0.005);
  handset.add(port);

  // Back camera island is actual geometry, revealed when the handset turns.
  const cameraIsland = new THREE.Mesh(
    new THREE.ExtrudeGeometry(roundedShape(0.84, 0.86, 0.18), {
      depth: 0.055, bevelEnabled: true, bevelSize: 0.025,
      bevelThickness: 0.014, bevelSegments: 3, curveSegments: 12
    }),
    graphite
  );
  cameraIsland.position.set(-0.51, 1.46, -0.22);
  cameraIsland.rotation.y = Math.PI;
  handset.add(cameraIsland);

  for (const position of [[-0.70, 1.69], [-0.35, 1.35]]) {
    const rim = new THREE.Mesh(
      new THREE.CylinderGeometry(0.167, 0.167, 0.055, 40),
      metal
    );
    rim.rotation.x = Math.PI / 2;
    rim.position.set(position[0], position[1], -0.285);
    handset.add(rim);
    const eye = new THREE.Mesh(
      new THREE.CylinderGeometry(0.118, 0.118, 0.061, 40),
      lens
    );
    eye.rotation.x = Math.PI / 2;
    eye.position.set(position[0], position[1], -0.317);
    handset.add(eye);
  }

  // USB-C cable travels along the actual bottom edge, then remains plugged in.
  const cable = new THREE.Group();
  handset.add(cable);
  const plug = new THREE.Mesh(
    new THREE.BoxGeometry(0.255, 0.36, 0.17),
    new THREE.MeshStandardMaterial({color: 0xd9dee5, roughness: 0.25, metalness: 0.23})
  );
  plug.position.set(0, -2.48, 0);
  cable.add(plug);
  const connector = new THREE.Mesh(
    new THREE.BoxGeometry(0.14, 0.14, 0.078),
    new THREE.MeshStandardMaterial({color: 0xadb9c6, metalness: 0.7, roughness: 0.26})
  );
  connector.position.set(0, -2.22, 0);
  cable.add(connector);

  const wire = new THREE.Mesh(
    new THREE.TubeGeometry(new THREE.CatmullRomCurve3([
      new THREE.Vector3(0, -2.62, 0),
      new THREE.Vector3(0, -2.98, 0),
      new THREE.Vector3(0.08, -3.35, 0),
      new THREE.Vector3(0.1, -3.59, 0)
    ]), 48, 0.056, 10, false),
    new THREE.MeshStandardMaterial({color: 0xe3e6eb, roughness: 0.6, metalness: 0.04})
  );
  cable.add(wire);
  cable.visible = false;

  function roundRect(ctx, x, y, width, height, radius) {
    const r = Math.min(radius, width / 2, height / 2);
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + width - r, y);
    ctx.quadraticCurveTo(x + width, y, x + width, y + r);
    ctx.lineTo(x + width, y + height - r);
    ctx.quadraticCurveTo(x + width, y + height, x + width - r, y + height);
    ctx.lineTo(x + r, y + height);
    ctx.quadraticCurveTo(x, y + height, x, y + height - r);
    ctx.lineTo(x, y + r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.closePath();
  }

  function drawDisplay(level, charging, offline) {
    if (!context) return;
    const ctx = context;
    const w = 540, h = 1120;
    ctx.clearRect(0, 0, w, h);
    ctx.save();
    roundRect(ctx, 0, 0, w, h, 76);
    ctx.clip();

    const background = ctx.createLinearGradient(0, 0, w, h);
    background.addColorStop(0, '#263b5b');
    background.addColorStop(0.54, '#19273e');
    background.addColorStop(1, '#0b1324');
    ctx.fillStyle = background;
    ctx.fillRect(0, 0, w, h);

    const haze = ctx.createRadialGradient(260, 485, 18, 260, 485, 450);
    haze.addColorStop(0, charging ? 'rgba(143,205,171,.19)' : 'rgba(149,185,227,.13)');
    haze.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = haze;
    ctx.fillRect(0, 0, w, h);

    // Status bar and dynamic island.
    ctx.fillStyle = '#f3f6ff';
    ctx.font = '600 28px -apple-system, system-ui, sans-serif';
    ctx.textAlign = 'left';
    ctx.fillText('9:41', 49, 81);
    ctx.textAlign = 'right';
    ctx.font = '600 24px -apple-system, system-ui, sans-serif';
    ctx.fillText('▰  ◕', 492, 81);
    ctx.fillStyle = '#030509';
    roundRect(ctx, 191, 23, 158, 49, 25);
    ctx.fill();

    ctx.textAlign = 'center';
    ctx.fillStyle = '#c2cfdd';
    ctx.font = '500 31px -apple-system, system-ui, sans-serif';
    ctx.fillText('iPhone', 270, 402);

    const bx = 147, by = 463, bw = 246, bh = 114;
    ctx.lineWidth = 7;
    ctx.strokeStyle = 'rgba(248,250,255,.95)';
    roundRect(ctx, bx, by, bw, bh, 23);
    ctx.stroke();
    ctx.fillStyle = '#f1f4f7';
    roundRect(ctx, bx + bw + 7, by + 37, 11, 40, 5);
    ctx.fill();

    const fillWidth = Math.max(11, (bw - 22) * Math.max(0, Math.min(100, level)) / 100);
    ctx.fillStyle = charging ? '#8bda9f' : level <= 20 ? '#f6a79b' : '#9ac5ac';
    roundRect(ctx, bx + 11, by + 11, fillWidth, bh - 22, 14);
    ctx.fill();

    if (charging) {
      ctx.fillStyle = '#ffffff';
      ctx.shadowColor = 'rgba(0,0,0,.4)';
      ctx.shadowBlur = 7;
      ctx.beginPath();
      ctx.moveTo(280, 478);
      ctx.lineTo(252, 523);
      ctx.lineTo(273, 523);
      ctx.lineTo(256, 558);
      ctx.lineTo(291, 511);
      ctx.lineTo(271, 511);
      ctx.closePath();
      ctx.fill();
      ctx.shadowBlur = 0;
    }

    ctx.fillStyle = '#fff';
    ctx.font = '300 136px -apple-system, system-ui, sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(String(level) + '%', 270, 736);
    ctx.fillStyle = '#c0ccda';
    ctx.font = '400 32px -apple-system, system-ui, sans-serif';
    ctx.fillText(charging ? 'Charging' : level <= 20 ? 'Low battery' : 'On battery', 270, 796);
    ctx.restore();
    displayTexture.needsUpdate = true;
  }

  const state = {
    scene: 0,
    phase: 0,
    level: 73,
    charging: false,
    offline: false
  };
  let lastDisplayKey = '';
  function updateState(next) {
    if (!next || !Number.isInteger(next.scene)) return;
    state.scene = Math.max(0, Math.min(5, next.scene));
    state.phase = Math.max(0, Math.min(1, Number(next.phase) || 0));
    state.level = Math.max(0, Math.min(100, Math.round(Number(next.level) || 0)));
    state.charging = !!next.charging;
    state.offline = !!next.offline;
    const key = state.level + '|' + state.charging;
    if (lastDisplayKey !== key) {
      drawDisplay(state.level, state.charging, state.offline);
      lastDisplayKey = key;
    }
  }

  updateState(window.__firefly3DState || state);
  window.addEventListener('firefly:3d-state', function (event) {
    updateState(event.detail);
  });

  const poses = [
    {y: -0.28, x: -0.055, z: -0.03},
    {y: 0.18, x: 0.015, z: 0.035},
    {y: -0.12, x: 0.055, z: 0},
    {y: 0.13, x: 0.02, z: 0},
    {y: 0.72, x: -0.04, z: 0.035},
    {y: -0.23, x: 0, z: -0.02}
  ];
  let hoverX = 0, hoverY = 0, active = false, raf = 0, disposed = false;
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  function resize() {
    if (disposed) return;
    const width = Math.max(1, mount.clientWidth);
    const height = Math.max(1, mount.clientHeight);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
    renderer.setSize(width, height, false);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
  }

  function tick() {
    if (!active || disposed) { raf = 0; return; }
    const a = poses[state.scene], b = poses[Math.min(5, state.scene + 1)];
    const fraction = state.phase;
    const factor = reducedMotion.matches ? 1 : 0.105;
    const targetY = THREE.MathUtils.lerp(a.y, b.y, fraction) + hoverX * 0.12;
    const targetX = THREE.MathUtils.lerp(a.x, b.x, fraction) + hoverY * 0.075;
    const targetZ = THREE.MathUtils.lerp(a.z, b.z, fraction);
    handset.rotation.y = THREE.MathUtils.lerp(handset.rotation.y, targetY, factor);
    handset.rotation.x = THREE.MathUtils.lerp(handset.rotation.x, targetX, factor);
    handset.rotation.z = THREE.MathUtils.lerp(handset.rotation.z, targetZ, factor);

    const pluggedIn = state.scene === 2 || state.scene === 3;
    const plugProgress = state.scene === 2 ? Math.min(1, state.phase * 3.3) : pluggedIn ? 1 : 0;
    cable.visible = pluggedIn && plugProgress > 0.02;
    cable.position.y = -1.18 * (1 - plugProgress);

    renderer.render(scene, camera);
    raf = window.requestAnimationFrame(tick);
  }

  function start() {
    if (active || disposed) return;
    active = true;
    resize();
    tick();
    if (!wrapper.classList.contains('three-ready')) {
      wrapper.classList.add('three-ready');
    }
  }
  function stop() {
    active = false;
    if (raf) window.cancelAnimationFrame(raf);
    raf = 0;
  }

  mount.addEventListener('pointermove', function (event) {
    if (reducedMotion.matches) return;
    const rect = mount.getBoundingClientRect();
    hoverX = ((event.clientX - rect.left) / Math.max(rect.width, 1) - 0.5) * 2;
    hoverY = ((event.clientY - rect.top) / Math.max(rect.height, 1) - 0.5) * 2;
  });
  mount.addEventListener('pointerleave', function () {
    hoverX = 0; hoverY = 0;
  });
  canvas.addEventListener('webglcontextlost', function (event) {
    event.preventDefault();
    stop();
    wrapper.classList.remove('three-ready');
  });
  canvas.addEventListener('webglcontextrestored', function () {
    start();
  });
  if ('ResizeObserver' in window) new ResizeObserver(resize).observe(mount);
  else window.addEventListener('resize', resize);
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (entries) {
      if (entries[0].isIntersecting) start();
      else stop();
    }, {threshold: 0.01}).observe(mount);
  } else start();
}
