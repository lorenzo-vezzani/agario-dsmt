"use strict";

// ──────────────────────────────────────────────────────────
// CONSTANTS
// ──────────────────────────────────────────────────────────
const ARENA_W = 2000;
const ARENA_H = 2000;
const GRID_CELL = 100;
const ZOOM_STEP = 0.1;
const ZOOM_MIN  = 0.3;
const ZOOM_MAX  = 4.0;

// ──────────────────────────────────────────────────────────
// STATE
// ──────────────────────────────────────────────────────────
let ws            = null;
let latestBalls   = [];
let latestFood    = [];
let latestStats   = [];
let mouseX        = 0;
let mouseY        = 0;
let everConnected = false;
let sendTimer     = null;
let rafId         = null;
let final_stats   = null;
let isDead        = false;
let isGameOver    = false;
let playerWasAlive = false; // true if client is in latestBalls
let zoom          = 1.0;

const TRAIL_LEN   = 28;
const trailMap    = new Map();

// ──────────────────────────────────────────────────────────
// DOM REFS
// ──────────────────────────────────────────────────────────
const $mouseDot     = document.getElementById('mouse-dot');
const $loginScreen  = document.getElementById('login-screen');
const $gameScreen   = document.getElementById('game-screen');
const $canvas       = document.getElementById('arena-canvas');
const ctx           = $canvas.getContext('2d');
const $errorBox     = document.getElementById('error-box');
const $enterBtn     = document.getElementById('enter-btn');
const $quitBtn      = document.getElementById('quit-btn');
const $hudGame      = document.getElementById('hud-game');
const $hudPlayer    = document.getElementById('hud-player');
const $hudCount     = document.getElementById('hud-count');
const $hudZoomVal   = document.getElementById('hud-zoom-val');
const $prePanel     = document.getElementById('pre-panel');
const $deathPanel   = document.getElementById('death-panel');
const $deathLb      = document.getElementById('death-leaderboard');
const $rejoinBtn    = document.getElementById('rejoin-btn');
const $gameoverPanel = document.getElementById('gameover-panel');
const $gameoverLb = document.getElementById('gameover-leaderboard');

// ──────────────────────────────────────────────────────────
// MOUSE TRACKING
// ──────────────────────────────────────────────────────────
document.addEventListener('mousemove', e => {
    mouseX = e.clientX;
    mouseY = e.clientY;
    $mouseDot.style.left = mouseX + 'px';
    $mouseDot.style.top  = mouseY + 'px';
});

// ──────────────────────────────────────────────────────────
// CANVAS SIZING — fills the flex remainder
// ──────────────────────────────────────────────────────────
function resizeCanvas() {
    $canvas.width  = $canvas.clientWidth  || window.innerWidth;
    $canvas.height = $canvas.clientHeight || (window.innerHeight - document.getElementById('hud').offsetHeight);
}

window.addEventListener('resize', resizeCanvas);

// ──────────────────────────────────────────────────────────
// CAMERA HELPERS
// ──────────────────────────────────────────────────────────

/**
 * Returns the arena-space position of the camera center.
 * We center on our ball; if not found, center on arena.
 */
function getCameraCenter() {
    const me = latestBalls.find(b => b.id === INIT_PLAYER_ID);
    return me ? { x: me.x, y: me.y } : { x: ARENA_W / 2, y: ARENA_H / 2 };
}

/**
 * Convert arena coords → canvas pixels, given current camera.
 * cam = { x, y } arena-space center, zoom = current zoom.
 * Canvas center = ($canvas.width/2, $canvas.height/2).
 */
function a2c(ax, ay, cam) {
    const cx = $canvas.width  / 2 + (ax - cam.x) * zoom;
    const cy = $canvas.height / 2 + (ay - cam.y) * zoom;
    return [cx, cy];
}

/**
 * Convert canvas pixel coords → arena units.
 */
function c2a(px, py, cam) {
    return [
        cam.x + (px - $canvas.width  / 2) / zoom,
        cam.y + (py - $canvas.height / 2) / zoom,
    ];
}

// ──────────────────────────────────────────────────────────
// DIRECTION COMPUTATION  (mouse → arena direction)
// ──────────────────────────────────────────────────────────
function computeDir() {
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

// ──────────────────────────────────────────────────────────
// WS SEND
// ──────────────────────────────────────────────────────────
function sendDir() {
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    const [dx, dy] = computeDir();
    ws.send(`{"dx":${dx.toFixed(4)},"dy":${dy.toFixed(4)}}`);
}

// ──────────────────────────────────────────────────────────
// COLOR PALETTE
// ──────────────────────────────────────────────────────────
function idToHue(id) {
    let h = 5381;
    for (let i = 0; i < id.length; i++) h = ((h * 33) ^ id.charCodeAt(i)) >>> 0;
    return h % 360;
}

const colorCache = new Map();
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

// ──────────────────────────────────────────────────────────
// RENDERING
// ──────────────────────────────────────────────────────────
function renderFrame() {
    const W = $canvas.width, H = $canvas.height;
    if (!W || !H) { rafId = requestAnimationFrame(renderFrame); return; }

    const cam = getCameraCenter();

    // ── Background
    ctx.fillStyle = '#080b10';
    ctx.fillRect(0, 0, W, H);

    // ── Moving grid (parallax with the arena)
    //    Grid lines are spaced GRID_CELL * zoom canvas-pixels apart.
    //    Offset shifts as the camera moves so the grid appears to scroll.
    {
        const gs = GRID_CELL * zoom;                      // canvas-space cell size
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

    // ── Arena border (the finite playing field boundary)
    {
        const [bx0, by0] = a2c(0,       0,       cam);
        const [bx1, by1] = a2c(ARENA_W, ARENA_H, cam);
        ctx.strokeStyle = 'rgba(0,229,255,0.30)';
        ctx.lineWidth = 2;
        ctx.strokeRect(bx0, by0, bx1 - bx0, by1 - by0);

        // subtle inner fill to distinguish "outside" from "inside"
        ctx.fillStyle = 'rgba(0,229,255,0.012)';
        ctx.fillRect(bx0, by0, bx1 - bx0, by1 - by0);
    }

    // ── Direction line (mouse → my ball)
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

    // ── Food dots
    for (const dot of latestFood) {
        const [fx, fy] = a2c(dot.x, dot.y, cam);
        const fr = Math.abs(dot.r) * zoom;

        // Skip if completely off-screen
        if (fx + fr * 4 < 0 || fx - fr * 4 > W || fy + fr * 4 < 0 || fy - fr * 4 > H) continue;

        // Glow
        const fg = ctx.createRadialGradient(fx, fy, 0, fx, fy, fr * 3);
        fg.addColorStop(0, 'rgba(0,229,255,0.32)');
        fg.addColorStop(1, 'transparent');
        ctx.beginPath(); ctx.arc(fx, fy, fr * 3, 0, Math.PI * 2);
        ctx.fillStyle = fg; ctx.fill();

        // Dot
        ctx.beginPath(); ctx.arc(fx, fy, Math.max(1.5, fr), 0, Math.PI * 2);
        ctx.fillStyle = (dot.r < 0) ? '#ff0088' : '#00e5ff';
        ctx.fill();
    }

    // ── Update trail history (arena space, before drawing)
    for (const ball of latestBalls) {
        if (!trailMap.has(ball.id)) trailMap.set(ball.id, []);
        const hist = trailMap.get(ball.id);
        // only push if moved enough (avoids duplicates at low framerate)
        const last = hist[hist.length - 1];
        if (!last || Math.hypot(ball.x - last.x, ball.y - last.y) > 1.5) {
            hist.push({ x: ball.x, y: ball.y });
            if (hist.length > TRAIL_LEN) hist.shift();
        }
    }
    // Remove trails for balls no longer present
    const activeBallIds = new Set(latestBalls.map(b => b.id));
    for (const id of trailMap.keys()) {
        if (!activeBallIds.has(id)) trailMap.delete(id);
    }

    // ── Balls (trail first, then ball on top)
    for (const ball of latestBalls) {
        const [cx, cy] = a2c(ball.x, ball.y, cam);
        const r  = (ball.r || 20) * zoom;
        const isMe = ball.id === INIT_PLAYER_ID;
        const col = getColor(ball.id);

        // Skip if completely off-screen
        if (cx + r * 3 < 0 || cx - r * 3 > W || cy + r * 3 < 0 || cy - r * 3 > H) continue;

        // ── Trail
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

        // ── Outer glow halo (stays outside but transparent — purely cosmetic)
        const grd = ctx.createRadialGradient(cx, cy, r * 0.4, cx, cy, r * 2.2);
        grd.addColorStop(0, col.glow);
        grd.addColorStop(1, 'transparent');
        ctx.beginPath();
        ctx.arc(cx, cy, r * 2.2, 0, Math.PI * 2);
        ctx.fillStyle = grd;
        ctx.fill();

        // ── Body gradient
        const bg = ctx.createRadialGradient(cx - r*0.3, cy - r*0.35, r*0.05, cx, cy, r);
        bg.addColorStop(0, col.fill);
        bg.addColorStop(1, col.fill2);
        ctx.beginPath(); 
        ctx.arc(cx, cy, r, 0, Math.PI * 2);
        ctx.fillStyle = bg;
        ctx.fill();

        // ── Inner rim glow (replaces the outer rings — stays strictly inside the border)
        if (isMe) {
            // bright inner rim
            const rim = ctx.createRadialGradient(cx, cy, r * 0.72, cx, cy, r);
            rim.addColorStop(0, 'transparent');
            rim.addColorStop(1, col.ring);
            ctx.beginPath(); 
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.fillStyle = rim;
            ctx.fill();
        }

        // ── Specular highlight
        ctx.beginPath(); ctx.arc(cx - r*0.28, cy - r*0.3, r*0.22, 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(255,255,255,0.22)';
        ctx.fill();

        // ── Label inside ball
        const fontSize = Math.max(9, Math.min(r * 0.85, 22));
        ctx.font = `bold ${fontSize}px "Share Tech Mono", monospace`;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = isMe ? '#fff' : 'rgba(255,255,255,0.82)';
        ctx.fillText(ball.id.length > 7 ? ball.id.slice(0, 6) + '…' : ball.id, cx, cy);

        // ── "YOU" tag above own player
        if (isMe) {
            const tagSize = Math.max(8, r * 0.55);
            ctx.font = `${tagSize}px "Share Tech Mono", monospace`;
            ctx.fillStyle = col.label;
            ctx.fillText('YOU', cx, cy - r - tagSize - 2);
        }
    }

    // ── Mouse crosshair / dot on canvas
    {
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

    // ── Minimap (bottom-right corner)
    {
        const MM_SIZE   = 160;        // minimap square size in canvas pixels
        const MM_PAD    = 14;         // distance from canvas edge
        const MM_X      = W - MM_SIZE - MM_PAD;
        const MM_Y      = H - MM_SIZE - MM_PAD;
        const MM_SCALE  = MM_SIZE / Math.max(ARENA_W, ARENA_H);

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

    // ── Leaderboards
    drawBallsLeaderboard(W, H);
    drawStatsLeaderboard(W, H);

    $hudZoomVal.textContent = zoom.toFixed(1) + '×';
    rafId = requestAnimationFrame(renderFrame);
}

// ──────────────────────────────────────────────────────────
// LEADERBOARD HELPERS
// ──────────────────────────────────────────────────────────

// Shared panel drawing utility
// Returns the usable inner y start and the line height so callers can lay rows
function drawLBPanel(x, y, w, title) {
    const PAD = 8;
    // background
    ctx.fillStyle = 'rgba(2,13,4,0.82)';
    ctx.fillRect(x, y, w, 0); // height TBD — drawn per row
    return { PAD, x, y };
}

// Top-left: balls sorted by radius desc, showing id / radius / (x,y)
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

// Top-right: kill/death stats sorted by kills desc, then deaths asc
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
function renderDeathLeaderboard() {
    if (!$deathLb || !latestStats.length) return;

    const sorted = [...latestStats].sort((a, b) => b.k - a.k || a.d - b.d);

    const header = `
        <div class="lb-header">
            <span class="lb-rank">#</span>
            <span class="lb-name">Player</span>
            <span class="lb-k">K</span>
            <span class="lb-d">D</span>
        </div>`;

    const rows = sorted.map((s, i) => {
        const isMe = s.id === INIT_PLAYER_ID;
        const name = s.id.length > 14 ? s.id.slice(0, 13) + '…' : s.id;
        return `<div class="lb-row${isMe ? ' lb-me' : ''}">
            <span class="lb-rank">${i + 1}</span>
            <span class="lb-name">${name}</span>
            <span class="lb-k">${s.k}</span>
            <span class="lb-d">${s.d}</span>
        </div>`;
    }).join('');

    $deathLb.innerHTML = header + rows;
}

// ──────────────────────────────────────────────────────────
// SCREEN TRANSITIONS
// ──────────────────────────────────────────────────────────
function showError(msg) {
    $errorBox.textContent = '> ' + msg;
    $errorBox.classList.add('visible');
    $enterBtn.disabled  = false;
    $enterBtn.textContent = '▶ Enter';
}

function enterGame() {
    everConnected = true;
    isDead        = false;
    playerWasAlive = false;
    $hudGame.textContent   = INIT_GAME_ID;
    $hudPlayer.textContent = INIT_PLAYER_ID;
    $errorBox.classList.remove('visible');
    $loginScreen.style.display = 'none';
    $gameScreen.classList.add('active');
    // Reset zoom on new game
    zoom = 1.0;
    resizeCanvas();
    rafId = requestAnimationFrame(renderFrame);
    sendTimer = setInterval(sendDir, 20);
}

function leaveGame(errMsg) {
    cancelAnimationFrame(rafId);
    clearInterval(sendTimer);
    everConnected = false;
    isDead = false;
    playerWasAlive = false;
    isGameOver = false;
    latestBalls = [];
    latestFood = [];
    latestStats = [];
    trailMap.clear();
    $gameScreen.classList.remove('active');
    $loginScreen.style.display = 'flex';
    $deathPanel.style.display = 'none';
    $prePanel.style.display   = 'block';
    $enterBtn.disabled = false;
    $enterBtn.textContent = '▶ Enter';
    if (errMsg) showError(errMsg);
    else $errorBox.classList.remove('visible');
}

// ──────────────────────────────────────────────────────────
// DEATH DETECTION & DEATH PANEL
// ──────────────────────────────────────────────────────────

/**
 * Called once when the server state no longer contains the player's ball,
 * after the player was known to be alive. The WS stays open.
 */
function onPlayerKilled() {
    isDead         = true;
    playerWasAlive = false;

    // Stop rendering & sending direction
    cancelAnimationFrame(rafId);
    rafId = null;
    clearInterval(sendTimer);
    sendTimer = null;

    // Switch back to the pre-game screen, but show death panel
    $gameScreen.classList.remove('active');
    $loginScreen.style.display = 'flex';
    $prePanel.style.display    = 'none';
    $deathPanel.style.display  = 'block';

    renderDeathLeaderboard();
}

function rejoin() {
    if (!ws || ws.readyState !== WebSocket.OPEN) return;

    isDead = false;
    playerWasAlive = false;

    $deathPanel.style.display  = 'none';
    $loginScreen.style.display = 'none';
    $gameScreen.classList.add('active');

    // Signal rejoin
    ws.send("rejoin");

    resizeCanvas();
    rafId = requestAnimationFrame(renderFrame);
    sendTimer = setInterval(sendDir, 20);
}

$rejoinBtn.addEventListener('click', rejoin);

function onGameOver(data) {
    isGameOver     = true;
    isDead         = false;
    playerWasAlive = false;

    cancelAnimationFrame(rafId); rafId = null;
    clearInterval(sendTimer);    sendTimer = null;

    $gameScreen.classList.remove('active');
    $loginScreen.style.display = 'flex';
    $prePanel.style.display    = 'none';
    $deathPanel.style.display  = 'none';
    $gameoverPanel.style.display = 'block';

    // ── ordered_balls leaderboard (posizione finale)
    const balls = Array.isArray(data.ordered_balls) ? data.ordered_balls : [];
    const stats = Array.isArray(data.stats)         ? data.stats         : [];

    // Mappa id → K/D per join veloce
    const statsMap = new Map(stats.map(s => [s.id, s]));

    const ballRows = balls.map((b, i) => {
        const isMe = b.id === INIT_PLAYER_ID;
        const s    = statsMap.get(b.id) || { k: '—', d: '—' };
        const name = b.id.length > 14 ? b.id.slice(0, 13) + '…' : b.id;
        return `<div class="lb-row${isMe ? ' lb-me' : ''}">
            <span class="lb-rank">${i + 1}</span>
            <span class="lb-name">${name}</span>
            <span class="lb-k">${s.k}</span>
            <span class="lb-d">${s.d}</span>
        </div>`;
    }).join('');

    $gameoverLb.innerHTML = `
        <div class="lb-header">
            <span class="lb-rank">#</span>
            <span class="lb-name">Player</span>
            <span class="lb-k">K</span>
            <span class="lb-d">D</span>
        </div>` + ballRows;
}

// ──────────────────────────────────────────────────────────
// WEBSOCKET CONNECT
// ──────────────────────────────────────────────────────────
function connect(hostIp, hostPort, gameId, playerId) {

    if (!hostIp || !hostPort || !gameId || !playerId) {
        showError('ERROR: Not all connection parameters have been specified');
        return;
    }

    $errorBox.classList.remove('visible');
    $enterBtn.disabled = true;
    $enterBtn.textContent = '... Entering';
    everConnected = false;

    const url = `wss://${hostIp}:${hostPort}/ws/${encodeURIComponent(gameId)}/${encodeURIComponent(playerId)}`;

    try {
        ws = new WebSocket(url);
    } catch (e) {
        showError(`ERROR: Address not valid — ${e.message}`);
        return;
    }

    ws.onopen = () => { /* waiting for first message */ };

    ws.onmessage = e => {
        let data;
        try { data = JSON.parse(e.data); } catch (_) { return; }

        switch (data.type) {
            case "state":
                if (Array.isArray(data.balls)) latestBalls = data.balls;
                if (Array.isArray(data.food))  latestFood  = data.food;
                if (Array.isArray(data.stats)) latestStats = data.stats;

                // ── Death detection (only while actively in game)
                if (everConnected && !isDead) {
                    const meAlive = latestBalls.some(b => b.id === INIT_PLAYER_ID);
                    if (meAlive) {
                        playerWasAlive = true;
                    } else if (playerWasAlive) {
                        onPlayerKilled();
                    }
                }

                // Update live leaderboard while spectating after death
                if (isDead) renderDeathLeaderboard();
                break;

            case "gameover":
                final_stats = data;
                onGameOver(data);
                break;

            default: 
                console.warn("unknown message type", data.type);
        }

        if (!everConnected) enterGame();
    };

    ws.onclose = e => {
        if (!everConnected) {
            if (e.code === 1008) {
                showError(`ERROR: game "${INIT_GAME_ID}" not found on server  [code 1008]`);
            } else if (e.code === 1006) {
                showError(`ERROR: Connection closed by ${hostIp}:${hostPort} [code 1006]`);
            } else {
                showError(`ERROR: Connection refused [code ${e.code}]`);
            }
        } else if (!isDead && !isGameOver) {
            leaveGame(`DISCONNECTED: code ${e.code}`);
        }
    };

    ws.onerror = () => { /* onclose fires right after */ };
}

// ──────────────────────────────────────────────────────────
// QUIT
// ──────────────────────────────────────────────────────────
$quitBtn.addEventListener('click', () => {
    if (ws) {
        ws.onclose = null;
        ws.close(1000, 'quit');
    }
    leaveGame(null);
});

// ──────────────────────────────────────────────────────────
// KEYBOARD
// ──────────────────────────────────────────────────────────
document.addEventListener('keydown', e => {
    // Login screen: Enter to connect
    if (e.key === 'Enter' && $loginScreen.style.display !== 'none') {
        connect(
            INIT_HOST_IP,
            INIT_HOST_PORT,
            INIT_GAME_ID,
            INIT_PLAYER_ID
        );
        return;
    }

    // Game screen zoom controls
    if ($gameScreen.classList.contains('active')) {
        if (e.key === 'q' || e.key === 'Q') {
            zoom = Math.max(ZOOM_MIN, parseFloat((zoom - ZOOM_STEP).toFixed(2)));
        } else if (e.key === 'p' || e.key === 'P') {
            zoom = Math.min(ZOOM_MAX, parseFloat((zoom + ZOOM_STEP).toFixed(2)));
        }
    }
});

$enterBtn.addEventListener('click', () => {
    connect(
        INIT_HOST_IP,
        INIT_HOST_PORT,
        INIT_GAME_ID,
        INIT_PLAYER_ID
    )
});