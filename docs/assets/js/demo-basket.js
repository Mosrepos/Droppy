/**
 * Demo Basket - Part 2: Drag to basket, jiggle, basket peek
 * Handles the floating basket demo sequence
 */

/**
 * Start the basket demo sequence (Part 2)
 * Called after shelf demo completes the rename animation
 */
function startBasketDemo() {
    const demoSection = document.querySelector('.macbook-section');
    const shelfEl = document.getElementById('shelf');
    const dragCursor = document.getElementById('dragCursor');
    const zipFile = document.getElementById('zipFile');

    if (!demoSection || !dragCursor) {
        console.log('Missing elements for basket demo');
        return;
    }

    const demoRect = demoSection.getBoundingClientRect();

    // Get zip file position
    let startX, startY;
    if (zipFile) {
        const zipRect = zipFile.getBoundingClientRect();
        startX = zipRect.left + zipRect.width / 2;
        startY = zipRect.top + zipRect.height / 2;
    } else {
        const shelfRect = shelfEl.getBoundingClientRect();
        startX = shelfRect.left + shelfRect.width / 2;
        startY = shelfRect.top + 100;
    }

    // Step 1: Position drag cursor at file and show it
    dragCursor.style.transition = 'none';
    dragCursor.style.left = startX + 'px';
    dragCursor.style.top = startY + 'px';
    dragCursor.style.opacity = '1';

    // Hide the zip file (we're "picking it up")
    if (zipFile) {
        zipFile.style.transition = 'opacity 0.15s ease-out';
        zipFile.style.opacity = '0';
    }

    // Step 2: Move down and close shelf (faster)
    demoTimeout = setTimeout(() => {
        if (!demoRunning) return;

        // Recalculate rect in case page scrolled
        const freshRect = demoSection.getBoundingClientRect();
        const centerX = freshRect.left + freshRect.width / 2;
        const centerY = freshRect.top + freshRect.height / 2;

        // Animate cursor moving down (faster)
        dragCursor.style.transition = 'left 0.45s ease-out, top 0.45s ease-out';
        dragCursor.style.left = centerX + 'px';
        dragCursor.style.top = centerY + 'px';

        // Close shelf silently
        closeShelfSilent();

        // Step 3: Jiggle animation (faster)
        demoTimeout = setTimeout(() => {
            if (!demoRunning) return;

            animateJiggle(dragCursor, centerX, () => {
                if (!demoRunning) return;

                // Step 4: Show basket
                showBasket(centerX, centerY);

                // Step 5: Drop file into basket
                demoTimeout = setTimeout(() => {
                    if (!demoRunning) return;
                    dropIntoBasket();

                    // Step 6: Peek basket to edge and START MEDIA DEMO simultaneously
                    demoTimeout = setTimeout(() => {
                        if (!demoRunning) return;
                        peekBasketToEdge();

                        // Start media demo RIGHT AWAY (overlap with peek)
                        startMediaDemo();

                        // Step 7: Reset basket after media demo is underway
                        demoTimeout = setTimeout(() => {
                            if (!demoRunning) return;
                            hideBasketAndReset();
                        }, 1800);
                    }, 700);
                }, 500);
            });
        }, 500);
    }, 300);
}

/**
 * Animate the jiggle gesture
 */
function animateJiggle(element, baseX, callback) {
    const jiggles = [20, -20, 15, -15, 10, -10, 0];
    let index = 0;

    const jiggleInterval = setInterval(() => {
        if (!demoRunning || index >= jiggles.length) {
            clearInterval(jiggleInterval);
            element.style.transition = 'left 0.1s ease-out';
            element.style.left = baseX + 'px';
            setTimeout(() => {
                if (callback) callback();
            }, 100);
            return;
        }
        element.style.transition = 'left 0.06s ease-out';
        element.style.left = (baseX + jiggles[index]) + 'px';
        index++;
    }, 60);
}

/**
 * Show the basket at position with targeted state
 */
function showBasket(x, y) {
    const basket = document.getElementById('basket');
    if (!basket) return;

    basket.style.left = (x - 188) + 'px';
    basket.style.top = (y - 88) + 'px';
    basket.style.opacity = '1';
    basket.style.transform = 'scale(1)';

    // Change border to blue (targeted state)
    const basketBorder = document.getElementById('basketBorder');
    if (basketBorder) {
        basketBorder.style.borderColor = 'rgba(59, 130, 246, 0.6)';
    }
}

/**
 * Simulate dropping file into basket
 */
function dropIntoBasket() {
    const dragCursor = document.getElementById('dragCursor');
    const basketFileGrid = document.getElementById('basketFileGrid');

    // Hide drag cursor
    dragCursor.style.opacity = '0';

    // Update basket content
    if (basketFileGrid) {
        basketFileGrid.innerHTML = `
            <div class="flex flex-col items-center justify-center h-full -mt-4" style="animation: scaleIn 0.3s ease-out;">
                <div class="w-[60px] h-[60px] rounded-2xl bg-white/10 flex items-center justify-center mb-1.5">
                    <div class="w-11 h-11 rounded-[14px] bg-gradient-to-br from-stone-400 to-stone-600 flex items-center justify-center shadow-lg">
                        <svg class="w-6 h-6 text-white" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd" d="M4 4a2 2 0 012-2h4.586A2 2 0 0112 2.586L15.414 6A2 2 0 0116 7.414V16a2 2 0 01-2 2H6a2 2 0 01-2-2V4z" clip-rule="evenodd"/>
                        </svg>
                    </div>
                </div>
                <p class="text-white/85 text-[10px] font-medium">Hello!.zip</p>
                <p class="text-white/40 text-[10px]">2.6 MB</p>
            </div>
        `;
    }

    // Reset border to normal
    const basketBorder = document.getElementById('basketBorder');
    if (basketBorder) {
        basketBorder.style.borderColor = 'rgba(255, 255, 255, 0.2)';
    }
}

/**
 * Animate basket peeking to the edge (auto-hide)
 */
function peekBasketToEdge() {
    const basket = document.getElementById('basket');
    const demoSection = document.querySelector('.macbook-section');
    if (!basket || !demoSection) return;

    const demoRect = demoSection.getBoundingClientRect();

    // Animate to right edge with rotation (peek mode)
    basket.style.transition = 'all 0.55s ease-out';
    basket.style.left = (demoRect.right - 60) + 'px';
    basket.style.top = (demoRect.top + demoRect.height / 2 - 88) + 'px';
    basket.style.transform = 'scale(0.92) perspective(500px) rotateY(-10deg)';
}

/**
 * Hide basket and reset for next loop
 */
function hideBasketAndReset() {
    const basket = document.getElementById('basket');
    const dragCursor = document.getElementById('dragCursor');
    const basketFileGrid = document.getElementById('basketFileGrid');

    // Hide basket
    if (basket) {
        basket.style.opacity = '0';
        basket.style.transform = 'scale(0.9)';
    }

    // Reset drag cursor
    if (dragCursor) {
        dragCursor.style.opacity = '0';
        dragCursor.style.transition = '';
    }

    // Reset basket content
    if (basketFileGrid) {
        basketFileGrid.innerHTML = `
            <div class="flex flex-col items-center gap-2 text-center">
                <svg class="w-8 h-8 text-white/40" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"/>
                </svg>
                <span class="text-white/30 text-xs font-medium">Drop files here</span>
            </div>
        `;
    }

    // Reset shelf files
    resetShelfFiles();
}
