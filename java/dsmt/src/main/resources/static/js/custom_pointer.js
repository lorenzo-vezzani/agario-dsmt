
"use strict";

// Should have an empty div with id mouse-dot
const $mouseDot = document.getElementById('mouse-dot');

// Move this div to mimic the mouse movement
document.addEventListener('mousemove', e => {
    $mouseDot.style.left = e.clientX + 'px';
    $mouseDot.style.top  = e.clientY + 'px';
});