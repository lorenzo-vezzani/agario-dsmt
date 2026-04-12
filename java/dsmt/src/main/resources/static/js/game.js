"use strict";

//region GAME CONSTANTS ───────────────────────────────────────────────────────────
// Game constant, to draw and visualize
const ARENA_W = 2000;
const ARENA_H = 2000;
const GRID_CELL = 100;
const ZOOM_STEP = 0.1;
const ZOOM_MIN  = 0.3;
const ZOOM_MAX  = 4.0;

//endregion

//region STATE CONSTANTS ──────────────────────────────────────────────────────────
// Variables to
let ws = null;
let latestBalls = [];
let latestFood = [];
let latestStats = [];
let mouseX = 0;
let mouseY= 0;
let everConnected = false;
let sendTimer = null;
let rafId = null;
let final_stats= null;
let isDead = false;
let isGameOver = false;
let playerWasAlive = false;
let zoom = 1.0;

const TRAIL_LEN = 28;
const trailMap = new Map();

//endregion

//region REFRENCES ────────────────────────────────────────────────────────────────
// Document refrences

const $mouseDot = document.getElementById('mouse-dot');
const $loginScreen = document.getElementById('login-screen');
const $gameScreen = document.getElementById('game-screen');
const $canvas = document.getElementById('arena-canvas');
const ctx = $canvas.getContext('2d');
const $errorBox = document.getElementById('error-box');
const $enterBtn = document.getElementById('enter-btn');
const $quitBtn = document.getElementById('quit-btn');
const $hudGame = document.getElementById('hud-game');
const $hudPlayer = document.getElementById('hud-player');
const $hudCountAlive = document.getElementById('hud-count-alive');
const $hudCountSpec = document.getElementById('hud-count-spec');
const $hudCountTotal = document.getElementById('hud-count-total');
const $hudZoomVal = document.getElementById('hud-zoom-val');
const $prePanel = document.getElementById('pre-panel');
const $deathPanel = document.getElementById('death-panel');
const $deathLb = document.getElementById('death-leaderboard');
const $rejoinBtn = document.getElementById('rejoin-btn');
const $gameoverPanel = document.getElementById('gameover-panel');
const $gameoverLb = document.getElementById('gameover-leaderboard');

//endregion

//region CAMERA, COORDINATES CONVERSION ───────────────────────────────────────────
// Function getCamerCenter, Coordinate conversion (canvas <-> arena)

/**
 * Returns the position of the camera center in arena coordinates
 * If the player is alive is centered on the ball,
 * otherwise it's centered on the arena.
 */
function getCameraCenter() {
    // Check if ball is present (alive)
    const myBall = latestBalls.find(b => b.id === INIT_PLAYER_ID);

    if(myBall){
        // If alive return the coordinate of the ball
        return {
            x: myBall.x,
            y: myBall.y
        };
    } else {
        // Otherwise return the center of the arena
        return {
            x: ARENA_W / 2,
            y: ARENA_H / 2
        };
    }
}

/**
 * Convert arena coords → canvas pixels, given current camera position.
 * cam = {x, y} arena-space center, zoom = current zoom.
 * Canvas center = ($canvas.width/2, $canvas.height/2).
 */
function a2c(ax, ay, cam) {
    const cx = $canvas.width  / 2 + (ax - cam.x) * zoom;
    const cy = $canvas.height / 2 + (ay - cam.y) * zoom;
    return [cx, cy];
}

/**
 * Convert canvas pixel coords into arena units.
 * @param px X coordinate
 * @param py Y coordinate
 * @param cam Current camera position {x, y}
 * @returns {*[]} X and Y coordinates in arena units
 */
function c2a(px, py, cam) {
    return [
        cam.x + (px - $canvas.width  / 2) / zoom,
        cam.y + (py - $canvas.height / 2) / zoom,
    ];
}

//endregion

//region DIRECTION ────────────────────────────────────────────────────────────────
// Direction computation, Direction send via WebSocket

/**
 * Computes the direction of the player's ball.
 * Take mouse position and ball position
 * @returns {number[]} Returns [dx, dy]
 */
function computeDirection() {
    const me = latestBalls.find(b => b.id === INIT_PLAYER_ID);
    if (!me) return [0, 0];

    const cam = getCameraCenter();
    const r   = $canvas.getBoundingClientRect();
    const [mx, my] = c2a(mouseX - r.left, mouseY - r.top, cam);

    const vx = mx - me.x;
    const vy = my - me.y;
    const len = Math.hypot(vx, vy);
    if (len < 0.5) return [0, 0];
    return [vx / len, vy / len];
}

/**
 * Sends the computed direction to the Game Process via the webSocket
 */
function sendDirection() {
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    const [dx, dy] = computeDirection();
    ws.send(`{"dx":${dx.toFixed(4)},"dy":${dy.toFixed(4)}}`);
}

//endregion

//region COLOR Helpers ────────────────────────────────────────────────────────────
// Color mapping function ( Player -> colour)

function idToHue(id) {
    let h = 5381;
    for (let i = 0; i < id.length; i++) h = ((h * 33) ^ id.charCodeAt(i)) >>> 0;
    return h % 360;
}

// Cached map of PlayerId <-> ColorSet
const colorCache = new Map();

/**
 * Get color set given a PlayerId
 * @param id PlayerId
 * @returns {'fill', 'fill2', 'glow', 'ring', 'label'} Set ot colors for the player
 */
function getColor(id) {
    if (!colorCache.has(id)) {
        const hue = idToHue(id);
        colorCache.set(id, {
            fill:  `hsl(${hue},90%,58%)`,
            fill2: `hsl(${hue},70%,32%)`,
            glow:  `hsla(${hue},100%,60%,0.18)`,
            ring:  `hsla(${hue},100%,70%,0.65)`,
            label: `hsl(${hue},100%,82%)`,
        });
    }
    return colorCache.get(id);
}
//endregion

//region RENDERING ────────────────────────────────────────────────────────────────
// Game screen rendering

/**
 * Resize canvas function
 */
function resizeCanvas() {
    $canvas.width  = $canvas.clientWidth  || window.innerWidth;
    $canvas.height = $canvas.clientHeight || (window.innerHeight - document.getElementById('hud').offsetHeight);
}

window.addEventListener('resize', resizeCanvas);

/**
 * Main render function
 */
function renderFrame() {

    const W = $canvas.width;
    const H = $canvas.height;
    if (!W || !H) {
        rafId = requestAnimationFrame(renderFrame);
        return;
    }

    // 0) Get camera center coordinates (all is relative to it)
    const cam = getCameraCenter();

    // 1) Draw background
    rf_drawBackground(ctx, W, H);

    // 2) Draw lines (vertical and horizontal
    rf_drawGrid(ctx, W, H, GRID_CELL, zoom, cam);

    // 3) Arena boundary
    rf_drawArena(ctx, a2c, cam, ARENA_W, ARENA_H);

    // 4) Direction line (ball to mouse)
    rf_drawDirectionLine(ctx, latestBalls, INIT_PLAYER_ID, a2c, cam, $canvas, mouseX, mouseY);

    // 5) Food dots
    rf_drawFood(ctx, latestFood, a2c, cam, zoom, W, H);

    // 6) Update trail positions
    rf_updateTrails(latestBalls, trailMap, TRAIL_LEN);

    // 7) Draw balls
    rf_drawBalls(ctx, latestBalls, trailMap, a2c, cam, zoom, W, H, INIT_PLAYER_ID, getColor, idToHue);

    // 8) Mouse target (tracking)
    rf_drawMouseTarget(ctx, $canvas, mouseX, mouseY, W, H);

    // 9) Minimap
    rf_drawMinimap(ctx, latestBalls, INIT_PLAYER_ID, idToHue, W, H, ARENA_W, ARENA_H);

    // 10) Ball leaderboard
    rf_drawBallsLeaderboard(ctx, latestBalls, INIT_PLAYER_ID, idToHue, W, H);

    // 11) Statistics leaderboard
    rf_drawStatsLeaderboard(ctx, latestStats, INIT_PLAYER_ID, idToHue, W, H);

    // 12) Update players count in head-up display
    rf_updateHudPlayersCounts(latestBalls, latestStats);

    $hudZoomVal.textContent = zoom.toFixed(1) + '×';
    rafId = requestAnimationFrame(renderFrame);
}

function rf_drawBackground(ctx, W, H){
    ctx.fillStyle = '#080b10';
    ctx.fillRect(0, 0, W, H);
}

function rf_drawGrid(ctx, W, H, GRID_CELL, zoom, cam){
    // Grid lines are spaced GRID_CELL * zoom
    // Drawn to represent movement to the client if nothing else is on screen

    // canvas-space cell size
    const gs = GRID_CELL * zoom;

    // canvas-pixel corresponding to arena (0,0)
    const originX = W / 2 - cam.x * zoom;
    const originY = H / 2 - cam.y * zoom;

    // first visible grid line index
    const startIX = Math.floor(-originX / gs);
    const startIY = Math.floor(-originY / gs);

    ctx.strokeStyle = 'rgba(0,229,255,0.06)';
    ctx.lineWidth = 1;
    ctx.beginPath();

    // vertical lines
    for (let i = startIX - 1; ; i++) {
        const px = Math.round(originX + i * gs) + 0.5;
        if (px > W) break;
        ctx.moveTo(px, 0); ctx.lineTo(px, H);
    }

    // horizontal lines
    for (let i = startIY - 1; ; i++) {
        const py = Math.round(originY + i * gs) + 0.5;
        if (py > H) break;
        ctx.moveTo(0, py); ctx.lineTo(W, py);
    }
    ctx.stroke();
}

function rf_drawArena(ctx, a2c, cam, ARENA_W, ARENA_H){
    const [bx0, by0] = a2c(0, 0, cam);
    const [bx1, by1] = a2c(ARENA_W, ARENA_H, cam);
    ctx.strokeStyle = 'rgba(0,229,255,0.30)';
    ctx.lineWidth = 2;
    ctx.strokeRect(bx0, by0, bx1 - bx0, by1 - by0);

    // inner fill to mark OUT from IN
    ctx.fillStyle = 'rgba(0,229,255,0.012)';
    ctx.fillRect(bx0, by0, bx1 - bx0, by1 - by0);
}

function rf_drawDirectionLine(ctx, latestBalls, INIT_PLAYER_ID, a2c, cam, canvas, mouseX, mouseY){
    const myBall = latestBalls.find(b => b.id === INIT_PLAYER_ID);
    if (myBall) {
        const [bx, by] = a2c(myBall.x, myBall.y, cam);
        const r = $canvas.getBoundingClientRect();
        const mx = mouseX - r.left;
        const my = mouseY - r.top;
        ctx.beginPath();
        ctx.moveTo(bx, by);
        ctx.lineTo(mx, my);
        ctx.strokeStyle = 'rgba(255,61,113,0.18)';
        ctx.lineWidth = 1;
        ctx.setLineDash([4, 7]);
        ctx.stroke();
        ctx.setLineDash([]);
    }
}

function rf_drawFood(ctx, latestFood, a2c, cam, zoom, W, H){
    for (const dot of latestFood) {
        const [fx, fy] = a2c(dot.x, dot.y, cam);
        const fr = Math.abs(dot.r) * zoom;

        // Skip if completely off-screen
        if (
            fx + fr * 4 < 0 ||
            fx - fr * 4 > W ||
            fy + fr * 4 < 0 ||
            fy - fr * 4 > H
        ) continue;

        // Glow
        const fg = ctx.createRadialGradient(fx, fy, 0, fx, fy, fr * 3);
        fg.addColorStop(0, 'rgba(0,229,255,0.32)');
        fg.addColorStop(1, 'transparent');
        ctx.beginPath(); ctx.arc(fx, fy, fr * 3, 0, Math.PI * 2);
        ctx.fillStyle = fg; ctx.fill();

        // Foot element
        ctx.beginPath();
        ctx.arc(fx, fy, Math.max(1.5, fr), 0, Math.PI * 2);
        ctx.fillStyle = (dot.r < 0) ? '#ff0088' : '#00e5ff';
        ctx.fill();
    }
}

function rf_updateTrails(latestBalls, trailMap, TRAIL_LEN){
    // Loop over all balls
    for (const ball of latestBalls) {

        // Possible new ball
        if (!trailMap.has(ball.id))
            trailMap.set(ball.id, []);

        // get full trail
        const hist = trailMap.get(ball.id);

        // get last trail element
        const last = hist[hist.length - 1];

        // Push new element only if it moved enough (1,5)
        if (!last || Math.hypot(ball.x - last.x, ball.y - last.y) > 1.5) {
            hist.push({ x: ball.x, y: ball.y });
            if (hist.length > TRAIL_LEN) hist.shift();
        }
    }

    // Remove trails for dead players
    const activeBallIds = new Set(latestBalls.map(b => b.id));
    for (const id of trailMap.keys()) {
        if (!activeBallIds.has(id)) trailMap.delete(id);
    }
}

function rf_drawBalls(ctx, latestBalls, trailMap, a2c, cam, zoom, W, H, INIT_PLAYER_ID, getColor, idToHue){

    // Loop over all balls
    for (const ball of latestBalls) {

        const [cx, cy] = a2c(ball.x, ball.y, cam);
        const r = (ball.r || 20) * zoom;
        const isMe = ball.id === INIT_PLAYER_ID;
        const col = getColor(ball.id);

        // 7.0) Skip if completely off-screen
        if (
            cx + r * 3 < 0 ||
            cx - r * 3 > W ||
            cy + r * 3 < 0 ||
            cy - r * 3 > H
        ) continue;

        // 7.1) Draw trail
        const hist = trailMap.get(ball.id) || [];
        if (hist.length > 1) {
            const hue    = idToHue(ball.id);
            const trailR = (ball.r || 20) * zoom;
            for (let i = 1; i < hist.length; i++) {
                const t   = i / hist.length;
                const [x0, y0] = a2c(hist[i-1].x, hist[i-1].y, cam);
                const [x1, y1] = a2c(hist[i].x,   hist[i].y,   cam);
                const alpha = t * (isMe ? 0.55 : 0.28);
                const width = trailR * 2 * t * (isMe ? 0.55 : 0.38);
                ctx.beginPath();
                ctx.moveTo(x0, y0);
                ctx.lineTo(x1, y1);
                ctx.strokeStyle = `hsla(${hue},90%,60%,${alpha.toFixed(3)})`;
                ctx.lineWidth   = Math.max(1, width);
                ctx.lineCap     = 'round';
                ctx.stroke();
            }
        }

        // 7.2) Draw outer glow halo
        const grd = ctx.createRadialGradient(cx, cy, r * 0.4, cx, cy, r * 2.2);
        grd.addColorStop(0, col.glow);
        grd.addColorStop(1, 'transparent');
        ctx.beginPath();
        ctx.arc(cx, cy, r * 2.2, 0, Math.PI * 2);
        ctx.fillStyle = grd;
        ctx.fill();

        // 7.3) Draw body gradient
        const bg = ctx.createRadialGradient(cx - r*0.3, cy - r*0.35, r*0.05, cx, cy, r);
        bg.addColorStop(0, col.fill);
        bg.addColorStop(1, col.fill2);
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, Math.PI * 2);
        ctx.fillStyle = bg;
        ctx.fill();

        // 7.4) Inner rim glow for my ball
        if (isMe) {
            const rim = ctx.createRadialGradient(cx, cy, r * 0.72, cx, cy, r);
            rim.addColorStop(0, 'transparent');
            rim.addColorStop(1, col.ring);
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.fillStyle = rim;
            ctx.fill();
        }

        // 7.5) Specular highlight (like sun reflection)
        ctx.beginPath(); ctx.arc(cx - r*0.28, cy - r*0.3, r*0.22, 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(255,255,255,0.22)';
        ctx.fill();

        // 7.6) Label inside the ball
        const fontSize = Math.max(9, Math.min(r * 0.85, 22));
        ctx.font = `bold ${fontSize}px "Share Tech Mono", monospace`;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = isMe ? '#fff' : 'rgba(255,255,255,0.82)';
        ctx.fillText(ball.id.length > 7 ? ball.id.slice(0, 6) + '…' : ball.id, cx, cy);

        // 7.7) "YOU" tag above my ball
        if (isMe) {
            const tagSize = Math.max(8, r * 0.55);
            ctx.font = `${tagSize}px "Share Tech Mono", monospace`;
            ctx.fillStyle = col.label;
            ctx.fillText('YOU', cx, cy - r - tagSize - 2);
        }
    }
}

function rf_drawMouseTarget(ctx, canvas, mouseX, mouseY, W, H){
    const r = $canvas.getBoundingClientRect();
    const mx = mouseX - r.left;
    const my = mouseY - r.top;
    if (mx >= 0 && mx <= W && my >= 0 && my <= H) {
        const mg = ctx.createRadialGradient(mx, my, 0, mx, my, 18);
        mg.addColorStop(0, 'rgba(255,61,113,0.3)');
        mg.addColorStop(1, 'transparent');
        ctx.beginPath(); ctx.arc(mx, my, 18, 0, Math.PI * 2);
        ctx.fillStyle = mg; ctx.fill();

        ctx.beginPath(); ctx.arc(mx, my, 6, 0, Math.PI * 2);
        ctx.fillStyle = '#ff3d71'; ctx.fill();
    }
}

function rf_drawMinimap(ctx, latestBalls, INIT_PLAYER_ID, idToHue, W, H, ARENA_W, ARENA_H){
    const MM_SIZE = 160; // minimap square size in canvas pixels
    const MM_PAD = 14; // distance from canvas edge
    const MM_X = W - MM_SIZE - MM_PAD;
    const MM_Y = H - MM_SIZE - MM_PAD;
    const MM_SCALE = MM_SIZE / Math.max(ARENA_W, ARENA_H);

    // Background
    ctx.fillStyle = 'rgba(8,11,16,0.88)';
    ctx.fillRect(MM_X, MM_Y, MM_SIZE, MM_SIZE);

    // Border
    ctx.strokeStyle = 'rgba(0,229,255,0.22)';
    ctx.lineWidth = 1;
    ctx.strokeRect(MM_X + 0.5, MM_Y + 0.5, MM_SIZE - 1, MM_SIZE - 1);

    // Light grid overlay (4×4)
    ctx.strokeStyle = 'rgba(0,229,255,0.06)';
    ctx.lineWidth = 0.5;
    for (let i = 1; i < 4; i++) {
        const ox = MM_X + (MM_SIZE / 4) * i;
        const oy = MM_Y + (MM_SIZE / 4) * i;
        ctx.beginPath(); ctx.moveTo(ox, MM_Y); ctx.lineTo(ox, MM_Y + MM_SIZE); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(MM_X, oy); ctx.lineTo(MM_X + MM_SIZE, oy); ctx.stroke();
    }

    // Clip to minimap rect so dots don't overflow
    ctx.save();
    ctx.beginPath();
    ctx.rect(MM_X, MM_Y, MM_SIZE, MM_SIZE);
    ctx.clip();

    // Draw balls
    for (const ball of latestBalls) {
        const isMe = ball.id === INIT_PLAYER_ID;
        const hue  = idToHue(ball.id);
        const dotX = MM_X + ball.x * MM_SCALE;
        const dotY = MM_Y + ball.y * MM_SCALE;
        const dotR = isMe ? 5 : Math.max(2.5, (ball.r || 20) * MM_SCALE * 2);

        if (isMe) {
            // Glow for own ball
            const mg = ctx.createRadialGradient(dotX, dotY, 0, dotX, dotY, dotR * 2.5);
            mg.addColorStop(0, `hsla(${hue},100%,65%,0.5)`);
            mg.addColorStop(1, 'transparent');
            ctx.beginPath(); ctx.arc(dotX, dotY, dotR * 2.5, 0, Math.PI * 2);
            ctx.fillStyle = mg; ctx.fill();
        }

        ctx.beginPath();
        ctx.arc(dotX, dotY, dotR, 0, Math.PI * 2);
        ctx.fillStyle = isMe
            ? `hsl(${hue},100%,72%)`
            : `hsla(${hue},80%,58%,0.75)`;
        ctx.fill();
    }

    // "RADAR" label
    ctx.restore();
    ctx.font = '8px "Share Tech Mono", monospace';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    ctx.fillStyle = 'rgba(0,229,255,0.25)';
    ctx.fillText('RADAR', MM_X + 4, MM_Y + 4);
}

function rf_drawBallsLeaderboard(ctx, latestBalls, INIT_PLAYER_ID, idToHue, W, H){

    if (!latestBalls.length)
        return;

    const FONT_TITLE = '8px "Share Tech Mono", monospace';
    const FONT_ROW   = '10px "Share Tech Mono", monospace';
    const FONT_ME    = 'bold 10px "Share Tech Mono", monospace';
    const PAD   = 10;
    const LH    = 16;           // line height per row
    const TITLE_H = 18;
    const PW    = 230;          // panel width
    const PX    = 14;
    const PY    = 14;
    const MAX_H = H - PY - 14; // don't go past canvas bottom

    const sorted = [...latestBalls].sort((a, b) => (b.r || 0) - (a.r || 0));

    // How many rows fit?
    const maxRows = Math.floor((MAX_H - TITLE_H - PAD) / LH);
    const rows = sorted.slice(0, maxRows);
    const panelH = TITLE_H + PAD + rows.length * LH + PAD;

    // Background
    ctx.fillStyle = 'rgba(8,11,16,0.88)';
    ctx.fillRect(PX, PY, PW, panelH);
    ctx.strokeStyle = 'rgba(0,229,255,0.18)';
    ctx.lineWidth = 1;
    ctx.strokeRect(PX + 0.5, PY + 0.5, PW - 1, panelH - 1);

    // Title
    ctx.font = FONT_TITLE;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    ctx.fillStyle = 'rgba(0,255,136,0.32)';
    ctx.fillText('BALLS', PX + PAD, PY + 5);
    // column headers
    ctx.fillStyle = 'rgba(0,255,136,0.20)';
    ctx.fillText('PLAYER', PX + PAD, PY + 5);
    ctx.textAlign = 'right';
    ctx.fillText('RAD', PX + PW - PAD - 70, PY + 5);
    ctx.fillText('X', PX + PW - PAD - 32, PY + 5);
    ctx.fillText('Y', PX + PW - PAD, PY + 5);

    let rowY = PY + TITLE_H;

    rows.forEach((ball, i) => {
        const isMe = ball.id === INIT_PLAYER_ID;
        const hue  = idToHue(ball.id);

        // highlight row for own ball
        if (isMe) {
            ctx.fillStyle = `hsla(${hue},80%,40%,0.18)`;
            ctx.fillRect(PX + 1, rowY, PW - 2, LH);
            // left accent bar
            ctx.fillStyle = `hsl(${hue},100%,65%)`;
            ctx.fillRect(PX + 1, rowY, 2, LH);
        }

        ctx.font = isMe ? FONT_ME : FONT_ROW;
        const label = ball.id.length > 10 ? ball.id.slice(0, 9) + '…' : ball.id;
        const rad   = (ball.r || 0).toFixed(1);
        const bx    = Math.round(ball.x);
        const by    = Math.round(ball.y);

        ctx.textAlign = 'left';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = isMe ? `hsl(${hue},100%,75%)` : 'rgba(0,229,255,0.68)';
        ctx.fillText(`${i + 1}. ${label}`, PX + PAD + 4, rowY + LH / 2);

        ctx.textAlign = 'right';
        ctx.fillStyle = isMe ? `hsl(${hue},80%,70%)` : 'rgba(0,229,255,0.45)';
        ctx.fillText(rad, PX + PW - PAD - 70, rowY + LH / 2);
        ctx.fillText(bx, PX + PW - PAD - 32, rowY + LH / 2);
        ctx.fillText(by, PX + PW - PAD, rowY + LH / 2);

        rowY += LH;
    });
}

function rf_drawStatsLeaderboard(ctx, latestStats, INIT_PLAYER_ID, idToHue, W, H){

    if (!latestStats.length)
        return;

    const FONT_TITLE = '8px "Share Tech Mono", monospace';
    const FONT_ROW   = '10px "Share Tech Mono", monospace';
    const FONT_ME    = 'bold 10px "Share Tech Mono", monospace';
    const PAD   = 10;
    const LH    = 16;
    const TITLE_H = 18;
    const PW    = 210;
    const PX    = W - PW - 14;
    const PY    = 14;
    const MAX_H = H - PY - 14;

    const sorted = [...latestStats].sort((a, b) => {
        if (b.k !== a.k) return b.k - a.k;
        return a.d - b.d;
    });

    const maxRows = Math.floor((MAX_H - TITLE_H - PAD) / LH);
    const rows = sorted.slice(0, maxRows);
    const panelH = TITLE_H + PAD + rows.length * LH + PAD;

    // Background
    ctx.fillStyle = 'rgba(8,11,16,0.88)';
    ctx.fillRect(PX, PY, PW, panelH);
    ctx.strokeStyle = 'rgba(0,229,255,0.18)';
    ctx.lineWidth = 1;
    ctx.strokeRect(PX + 0.5, PY + 0.5, PW - 1, panelH - 1);

    // Column headers
    ctx.font = FONT_TITLE;
    ctx.textBaseline = 'top';
    ctx.fillStyle = 'rgba(0,229,255,0.20)';
    ctx.textAlign = 'left';
    ctx.fillText('PLAYER', PX + PAD, PY + 5);
    ctx.textAlign = 'right';
    ctx.fillStyle = 'rgba(0,229,255,0.28)';
    ctx.fillText('K', PX + PW - PAD - 26, PY + 5);
    ctx.fillStyle = 'rgba(255,61,113,0.28)';
    ctx.fillText('D', PX + PW - PAD, PY + 5);

    let rowY = PY + TITLE_H;

    rows.forEach((stat, i) => {
        const isMe = stat.id === INIT_PLAYER_ID;
        const hue  = idToHue(stat.id);

        if (isMe) {
            ctx.fillStyle = `hsla(${hue},80%,40%,0.18)`;
            ctx.fillRect(PX + 1, rowY, PW - 2, LH);
            ctx.fillStyle = `hsl(${hue},100%,65%)`;
            ctx.fillRect(PX + PW - 3, rowY, 2, LH); // right accent bar
        }

        ctx.font = isMe ? FONT_ME : FONT_ROW;
        const label = stat.id.length > 10 ? stat.id.slice(0, 9) + '…' : stat.id;

        ctx.textAlign = 'left';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = isMe ? `hsl(${hue},100%,75%)` : 'rgba(0,229,255,0.68)';
        ctx.fillText(`${i + 1}. ${label}`, PX + PAD + 4, rowY + LH / 2);

        // kills — green tint
        ctx.textAlign = 'right';
        ctx.fillStyle = isMe ? '#77eeee' : 'rgba(0,229,255,0.65)';
        ctx.fillText(stat.k, PX + PW - PAD - 26, rowY + LH / 2);

        // deaths — red tint
        ctx.fillStyle = isMe ? '#ff6680' : 'rgba(255,61,113,0.55)';
        ctx.fillText(stat.d, PX + PW - PAD, rowY + LH / 2);

        rowY += LH;
    });
}

function rf_updateHudPlayersCounts(latestBalls, latestStats) {
    const alive = latestBalls.length;
    const total = latestStats.length;
    const spec  = total - alive;

    $hudCountAlive.textContent = alive;
    $hudCountSpec.textContent  = spec;
    $hudCountTotal.textContent = total;
}

// ──────────────────────────────────────────────────────────
// LEADERBOARD HELPERS
// ──────────────────────────────────────────────────────────

/**
 * Draws the balls currently in game in the top-left of the screen, sorted by radius
 */
function drawBallsLeaderboard(W, H) {
    if (!latestBalls.length) return;

    const FONT_TITLE = '8px "Share Tech Mono", monospace';
    const FONT_ROW   = '10px "Share Tech Mono", monospace';
    const FONT_ME    = 'bold 10px "Share Tech Mono", monospace';
    const PAD   = 10;
    const LH    = 16;           // line height per row
    const TITLE_H = 18;
    const PW    = 230;          // panel width
    const PX    = 14;
    const PY    = 14;
    const MAX_H = H - PY - 14; // don't go past canvas bottom

    const sorted = [...latestBalls].sort((a, b) => (b.r || 0) - (a.r || 0));

    // How many rows fit?
    const maxRows = Math.floor((MAX_H - TITLE_H - PAD) / LH);
    const rows = sorted.slice(0, maxRows);
    const panelH = TITLE_H + PAD + rows.length * LH + PAD;

    // Background
    ctx.fillStyle = 'rgba(8,11,16,0.88)';
    ctx.fillRect(PX, PY, PW, panelH);
    ctx.strokeStyle = 'rgba(0,229,255,0.18)';
    ctx.lineWidth = 1;
    ctx.strokeRect(PX + 0.5, PY + 0.5, PW - 1, panelH - 1);

    // Title
    ctx.font = FONT_TITLE;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    ctx.fillStyle = 'rgba(0,255,136,0.32)';
    ctx.fillText('BALLS', PX + PAD, PY + 5);
    // column headers
    ctx.fillStyle = 'rgba(0,255,136,0.20)';
    ctx.fillText('PLAYER', PX + PAD, PY + 5);
    ctx.textAlign = 'right';
    ctx.fillText('RAD', PX + PW - PAD - 70, PY + 5);
    ctx.fillText('X', PX + PW - PAD - 32, PY + 5);
    ctx.fillText('Y', PX + PW - PAD, PY + 5);

    let rowY = PY + TITLE_H;

    rows.forEach((ball, i) => {
        const isMe = ball.id === INIT_PLAYER_ID;
        const hue  = idToHue(ball.id);

        // highlight row for own ball
        if (isMe) {
            ctx.fillStyle = `hsla(${hue},80%,40%,0.18)`;
            ctx.fillRect(PX + 1, rowY, PW - 2, LH);
            // left accent bar
            ctx.fillStyle = `hsl(${hue},100%,65%)`;
            ctx.fillRect(PX + 1, rowY, 2, LH);
        }

        ctx.font = isMe ? FONT_ME : FONT_ROW;
        const label = ball.id.length > 10 ? ball.id.slice(0, 9) + '…' : ball.id;
        const rad   = (ball.r || 0).toFixed(1);
        const bx    = Math.round(ball.x);
        const by    = Math.round(ball.y);

        ctx.textAlign = 'left';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = isMe ? `hsl(${hue},100%,75%)` : 'rgba(0,229,255,0.68)';
        ctx.fillText(`${i + 1}. ${label}`, PX + PAD + 4, rowY + LH / 2);

        ctx.textAlign = 'right';
        ctx.fillStyle = isMe ? `hsl(${hue},80%,70%)` : 'rgba(0,229,255,0.45)';
        ctx.fillText(rad, PX + PW - PAD - 70, rowY + LH / 2);
        ctx.fillText(bx, PX + PW - PAD - 32, rowY + LH / 2);
        ctx.fillText(by, PX + PW - PAD, rowY + LH / 2);

        rowY += LH;
    });
}

/**
 * Draws the statistics (kills, deaths) in the top-right of the screen
 */
function drawStatsLeaderboard(W, H) {
    if (!latestStats.length) return;

    const FONT_TITLE = '8px "Share Tech Mono", monospace';
    const FONT_ROW   = '10px "Share Tech Mono", monospace';
    const FONT_ME    = 'bold 10px "Share Tech Mono", monospace';
    const PAD   = 10;
    const LH    = 16;
    const TITLE_H = 18;
    const PW    = 210;
    const PX    = W - PW - 14;
    const PY    = 14;
    const MAX_H = H - PY - 14;

    const sorted = [...latestStats].sort((a, b) => {
        if (b.k !== a.k) return b.k - a.k;
        return a.d - b.d;
    });

    const maxRows = Math.floor((MAX_H - TITLE_H - PAD) / LH);
    const rows = sorted.slice(0, maxRows);
    const panelH = TITLE_H + PAD + rows.length * LH + PAD;

    // Background
    ctx.fillStyle = 'rgba(8,11,16,0.88)';
    ctx.fillRect(PX, PY, PW, panelH);
    ctx.strokeStyle = 'rgba(0,229,255,0.18)';
    ctx.lineWidth = 1;
    ctx.strokeRect(PX + 0.5, PY + 0.5, PW - 1, panelH - 1);

    // Column headers
    ctx.font = FONT_TITLE;
    ctx.textBaseline = 'top';
    ctx.fillStyle = 'rgba(0,229,255,0.20)';
    ctx.textAlign = 'left';
    ctx.fillText('PLAYER', PX + PAD, PY + 5);
    ctx.textAlign = 'right';
    ctx.fillStyle = 'rgba(0,229,255,0.28)';
    ctx.fillText('K', PX + PW - PAD - 26, PY + 5);
    ctx.fillStyle = 'rgba(255,61,113,0.28)';
    ctx.fillText('D', PX + PW - PAD, PY + 5);

    let rowY = PY + TITLE_H;

    rows.forEach((stat, i) => {
        const isMe = stat.id === INIT_PLAYER_ID;
        const hue  = idToHue(stat.id);

        if (isMe) {
            ctx.fillStyle = `hsla(${hue},80%,40%,0.18)`;
            ctx.fillRect(PX + 1, rowY, PW - 2, LH);
            ctx.fillStyle = `hsl(${hue},100%,65%)`;
            ctx.fillRect(PX + PW - 3, rowY, 2, LH); // right accent bar
        }

        ctx.font = isMe ? FONT_ME : FONT_ROW;
        const label = stat.id.length > 10 ? stat.id.slice(0, 9) + '…' : stat.id;

        ctx.textAlign = 'left';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = isMe ? `hsl(${hue},100%,75%)` : 'rgba(0,229,255,0.68)';
        ctx.fillText(`${i + 1}. ${label}`, PX + PAD + 4, rowY + LH / 2);

        // kills — green tint
        ctx.textAlign = 'right';
        ctx.fillStyle = isMe ? '#77eeee' : 'rgba(0,229,255,0.65)';
        ctx.fillText(stat.k, PX + PW - PAD - 26, rowY + LH / 2);

        // deaths — red tint
        ctx.fillStyle = isMe ? '#ff6680' : 'rgba(255,61,113,0.55)';
        ctx.fillText(stat.d, PX + PW - PAD, rowY + LH / 2);

        rowY += LH;
    });
}

// ──────────────────────────────────────────────────────────
// DEATH PANEL — HTML leaderboard (live while spectating)
// ──────────────────────────────────────────────────────────

/**
 * Renders the live leaderboard shown while spectating after death.
 * Merges latestBalls (for radius/alive status) with latestStats (K/D).
 * Players still alive show their current radius; dead players show '—'.
 * Sorted by kills desc, then deaths asc.
 */
function renderDeathLeaderboard() {
    if (!$deathLb) return;
    if (!latestStats.length && !latestBalls.length) return;

    // Build a quick-lookup map: id -> ball (only alive players)
    const ballMap = new Map(latestBalls.map(b => [b.id, b]));

    // Collect all known player IDs (alive OR with recorded stats)
    const allIds = new Set([
        ...latestBalls.map(b => b.id),
        ...latestStats.map(s => s.id),
    ]);

    // Build a unified entry per player
    const statsById = new Map(latestStats.map(s => [s.id, s]));
    const entries = [...allIds].map(id => {
        const s = statsById.get(id) || { k: 0, d: 0 };
        const b = ballMap.get(id);
        return {
            id,
            k: s.k,
            d: s.d,
            r: b != null ? Math.round(b.r) : null, // null = dead / not in arena
        };
    });

    // Sort: most kills first; tie-break by fewest deaths
    entries.sort((a, b) => b.k - a.k || a.d - b.d);

    const header = `
        <div class="lb-header">
            <span class="lb-rank">#</span>
            <span class="lb-name">Player</span>
            <span class="lb-r">SZ</span>
            <span class="lb-k">K</span>
            <span class="lb-d">D</span>
        </div>`;

    const rows = entries.map((e, i) => {
        const isMe   = e.id === INIT_PLAYER_ID;
        const isAlive = e.r != null;
        const name   = e.id.length > 14 ? e.id.slice(0, 13) + '…' : e.id;
        const sizeStr = isAlive ? e.r : '—';

        const cls = ['lb-row', isMe ? 'lb-me' : '', !isAlive ? 'lb-dead' : '']
            .filter(Boolean).join(' ');

        return `<div class="${cls}">
            <span class="lb-rank">${i + 1}</span>
            <span class="lb-name">${name}</span>
            <span class="lb-r">${sizeStr}</span>
            <span class="lb-k">${e.k}</span>
            <span class="lb-d">${e.d}</span>
        </div>`;
    }).join('');

    $deathLb.innerHTML = header + rows;
}

//endregion

//region SCREEN TRANSITIONS ───────────────────────────────────────────────────────
// Screen transitions (initial, game, killed, gameover, etc)

/**
 * Displays any error in the proper box
 * @param msg The (error) message to be visualized
 */
function showError(msg) {
    $errorBox.textContent = '> ' + msg;
    $errorBox.classList.add('visible');
    $enterBtn.disabled  = false;
    $enterBtn.textContent = '▶ Enter';
}

/**
 * Called upon entering the game, after authentication is completed
 * - Initializes/resets state variables
 * - Start animations
 */
function enterGame() {

    // Reset variables
    everConnected = true;
    isDead = false;
    playerWasAlive = false;
    $hudGame.textContent = INIT_GAME_ID;
    $hudPlayer.textContent = INIT_PLAYER_ID;
    zoom = 1.0;

    // Change screens
    $errorBox.classList.remove('visible');
    $loginScreen.style.display = 'none';
    $gameScreen.classList.add('active');

    // Start animations
    resizeCanvas();
    rafId = requestAnimationFrame(renderFrame);
    sendTimer = setInterval(sendDirection, 20);
}

/**
 * Called when the player is killed (ball not present)
 * - Sets state variables
 * - Stops animations
 * - Displays death panel (with live leaderboard)
 */
function onPlayerKilled() {

    // Reset variables
    isDead = true;
    playerWasAlive = false;

    // Stop rendering
    cancelAnimationFrame(rafId);
    clearInterval(sendTimer);
    rafId = null;
    sendTimer = null;

    // Switch back to pre-game screen, but now show death panel
    $gameScreen.classList.remove('active');
    $loginScreen.style.display = 'flex';
    $prePanel.style.display = 'none';
    $deathPanel.style.display = 'block';

    // Render live leaderboard
    renderDeathLeaderboard();
}

/**
 * Called when the game terminates (from server)
 * - Cancels animations, shows normal screen
 * - Visualize final data (Stats, Balls)
 * @param gameoverData JSON deserialized data, received from server
 */
function onGameOver(gameoverData) {
    // Reset variables
    isGameOver = true;
    isDead = false;
    playerWasAlive = false;

    // Cancel animation
    cancelAnimationFrame(rafId); rafId = null;
    clearInterval(sendTimer);    sendTimer = null;

    // Show normal screen
    $gameScreen.classList.remove('active');
    $loginScreen.style.display = 'flex';
    $prePanel.style.display    = 'none';
    $deathPanel.style.display  = 'none';
    $gameoverPanel.style.display = 'block';

    // Get the two arrays
    const balls = Array.isArray(gameoverData.ordered_balls) ? gameoverData.ordered_balls : [];
    const stats = Array.isArray(gameoverData.stats) ? gameoverData.stats : [];

    // Construct a map for the stats
    const statsMap = new Map(stats.map(s => [s.id, s]));

    // Loop over the ball array
    // Loop over the ball array (already ordered by server: 1st = winner)
    const ballRows = balls.map((b, i) => {
        const isMe = b.id === INIT_PLAYER_ID;
        const s    = statsMap.get(b.id) || { k: '—', d: '—' };
        const name = b.id.length > 14 ? b.id.slice(0, 13) + '…' : b.id;
        const size = b.r != null ? Math.round(b.r) : '—';

        return `<div class="lb-row${isMe ? ' lb-me' : ''}">
            <span class="lb-rank">${i + 1}</span>
            <span class="lb-name">${name}</span>
            <span class="lb-r">${size}</span>
            <span class="lb-k">${s.k}</span>
            <span class="lb-d">${s.d}</span>
        </div>`;
    }).join('');

    // Add header row and append balls list
    $gameoverLb.innerHTML = `
        <div class="lb-header">
            <span class="lb-rank">#</span>
            <span class="lb-name">Player</span>
            <span class="lb-r">SZ</span>
            <span class="lb-k">K</span>
            <span class="lb-d">D</span>
        </div>` + ballRows;
}

/**
 * Called when the player leaves the game
 * - Resets variables and animations
 * - Displays initial page
 * @param errMsg Optional error message to be visualized
 */
function leaveGame(errMsg) {

    // Stop animations
    cancelAnimationFrame(rafId);
    clearInterval(sendTimer);

    // Reset variables
    everConnected = false;
    isDead = false;
    playerWasAlive = false;
    isGameOver = false;
    latestBalls = [];
    latestFood = [];
    latestStats = [];

    // Clear client trail
    trailMap.clear();

    // Display initial screen
    $gameScreen.classList.remove('active');
    $loginScreen.style.display = 'flex';
    $deathPanel.style.display = 'none';
    $prePanel.style.display = 'block';
    $enterBtn.disabled = false;
    $enterBtn.textContent = '▶ Enter';

    // Maybe display message
    if (errMsg) showError(errMsg);
    else $errorBox.classList.remove('visible');
}

// Add leave listener to leave button
$quitBtn.addEventListener('click', () => {
    if (ws) {
        ws.onclose = null;
        ws.close(1000, 'quit');
    }
    leaveGame(null);
});

//endregion

//region WebSocket CONNECTION ─────────────────────────────────────────────────────
// - WebSocket connect() function
// - WebSocket rejoin() function, used after death while socket is still open

function connect(hostIp, hostPort, gameId, playerId, token) {

    if (!hostIp || !hostPort || !gameId || !playerId || !token) {
        showError('ERROR: Not all connection parameters have been specified');
        return;
    }

    $errorBox.classList.remove('visible');
    $enterBtn.disabled = true;
    $enterBtn.textContent = '... Entering';
    everConnected = false;

    // Connection URL
    const url = `wss://${hostIp}:${hostPort}/ws/${encodeURIComponent(gameId)}/${encodeURIComponent(playerId)}?token=${encodeURIComponent(token)}`;

    try {
        // This automatically initiates the authentication (using the token)
        ws = new WebSocket(url);
    } catch (e) {
        showError(`ERROR: Address not valid — ${e.message}`);
        return;
    }

    ws.onopen = () => {};

    // receive message
    ws.onmessage = e => {
        let data;
        try { data = JSON.parse(e.data); } catch (_) { return; }

        switch (data.type) {

            // Authentication terminated
            case "auth_ok":
                enterGame();
                break;

            case "state":
                // Save JSON fields for rendering
                if (Array.isArray(data.balls)) latestBalls = data.balls;
                if (Array.isArray(data.food))  latestFood  = data.food;
                if (Array.isArray(data.stats)) latestStats = data.stats;

                // Death detection (my ball not present)
                if (everConnected && !isDead) {
                    const meAlive = latestBalls.some(b => b.id === playerId);
                    if (meAlive) {
                        playerWasAlive = true;
                    } else if (playerWasAlive) {
                        onPlayerKilled();
                    }
                }

                // Update leaderboard while spectating after death
                if (isDead) renderDeathLeaderboard();
                break;

            // On gameover save final statistics for visualization
            case "gameover":
                final_stats = data;
                onGameOver(data);
                break;

            default: 
                console.warn("unknown message type", data.type);
        }
    };

    // If close just print the error code
    ws.onclose = e => {
        if (!everConnected) {
            if (e.code === 1008) {
                showError(`ERROR: Access denied or game "${gameId}" not found on server [code 1008]`);
            } else if (e.code === 1006) {
                showError(`ERROR: Connection closed by ${hostIp}:${hostPort} [code 1006]`);
            } else {
                showError(`ERROR: Connection refused [code ${e.code}]`);
            }
        } else if (!isDead && !isGameOver) {
            leaveGame(`DISCONNECTED: code ${e.code}`);
        }
    };

    ws.onerror = () => {};
}

function rejoin() {

    // Rejoin only makes sense with socket open
    if (!ws || ws.readyState !== WebSocket.OPEN) return;

    // Signal rejoin
    ws.send("rejoin");

    // Reset variables
    isDead = false;
    playerWasAlive = false;

    // Visualize game panel
    $deathPanel.style.display = 'none';
    $loginScreen.style.display = 'none';
    $gameScreen.classList.add('active');

    // Restart animations
    resizeCanvas();
    rafId = requestAnimationFrame(renderFrame);
    sendTimer = setInterval(sendDirection, 20);
}

// Link connect() function to 'ENTER' button
$enterBtn.addEventListener('click', () => {
    connect(
        INIT_HOST_IP,
        INIT_HOST_PORT,
        INIT_GAME_ID,
        INIT_PLAYER_ID,
        INIT_GAME_TOKEN
    )
});

// Link rejoin() function to 'REJOIN' button
$rejoinBtn.addEventListener('click', rejoin);

//endregion

//region MOUSE and KEYBOARD ───────────────────────────────────────────────────────
// Mouse tracking for direction, Keyboard listener for enter game (Enter) and zoom

// Mouse listener
document.addEventListener('mousemove', e => {
    mouseX = e.clientX;
    mouseY = e.clientY;
    $mouseDot.style.left = mouseX + 'px';
    $mouseDot.style.top  = mouseY + 'px';
});

// Keyboard listener
document.addEventListener('keydown', e => {

    // Enter to connect if on login screen
    if (e.key === 'Enter' && $loginScreen.style.display !== 'none') {
        connect(
            INIT_HOST_IP,
            INIT_HOST_PORT,
            INIT_GAME_ID,
            INIT_PLAYER_ID,
            INIT_GAME_TOKEN
        );
        return;
    }

    // Game screen zoom (only if in game)
    if ($gameScreen.classList.contains('active')) {
        if (e.key === 'q' || e.key === 'Q') {
            zoom = Math.max(ZOOM_MIN, parseFloat((zoom - ZOOM_STEP).toFixed(2)));
        } else if (e.key === 'p' || e.key === 'P') {
            zoom = Math.min(ZOOM_MAX, parseFloat((zoom + ZOOM_STEP).toFixed(2)));
        }
    }
});

//endregion