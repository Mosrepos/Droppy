/**
 * Demo Media - Part 3: Media Player demonstration
 * Shows the notch media player: small HUD → hover title scroll → expanded player
 */

/**
 * Start the media player demo sequence (Part 3)
 * Called after basket demo completes the peek animation
 */
function startMediaDemo() {
    if (!demoRunning) return;

    // Step 1: Show small media HUD in notch (album art + visualizer)
    showSmallMediaPlayer();
}

/**
 * Show the small notch media player with album art and visualizer
 * Transforms notch into a pill shape with media content
 */
function showSmallMediaPlayer() {
    const notchBar = document.getElementById('notchBar');
    const cameraDot = document.getElementById('cameraDot');
    const notchMediaContent = document.getElementById('notchMediaContent');

    if (!notchBar || !notchMediaContent) {
        // Fallback: skip to shelf demo if elements missing
        demoTimeout = setTimeout(() => {
            if (demoRunning) {
                openShelf();
                startShelfDemo();
            }
        }, 500);
        return;
    }

    // Expand notch width (keep straight top, rounded bottom - it's a notch extending from top edge)
    notchBar.style.borderRadius = '0 0 20px 20px';
    notchBar.style.width = '280px';

    // Hide camera dot, show media content
    if (cameraDot) cameraDot.style.opacity = '0';
    notchMediaContent.style.opacity = '1';

    // Start visualizer animation
    startVisualizerAnimation();

    // After 1.5s, show hover state with scrolling title (faster)
    demoTimeout = setTimeout(() => {
        if (!demoRunning) return;
        showHoverState();
    }, 1500);
}

/**
 * Show the hover state with scrolling song title
 */
function showHoverState() {
    const scrollingTitle = document.getElementById('scrollingTitle');
    const notchBar = document.getElementById('notchBar');

    if (!scrollingTitle) {
        // Skip to expanded player
        demoTimeout = setTimeout(() => {
            if (demoRunning) showExpandedPlayer();
        }, 500);
        return;
    }

    // Make notch bottom corners straight so it connects with title panel
    if (notchBar) {
        notchBar.style.borderRadius = '0';
    }

    // Show scrolling title panel (expand height)
    scrollingTitle.style.opacity = '1';
    scrollingTitle.style.height = '36px';
    scrollingTitle.style.paddingTop = '0';
    scrollingTitle.style.paddingBottom = '8px';

    // Start marquee animation
    startMarqueeAnimation();

    // After 2s, expand to full player (faster)
    demoTimeout = setTimeout(() => {
        if (!demoRunning) return;
        showExpandedPlayer();
    }, 2000);
}

/**
 * Show the full expanded media player
 */
function showExpandedPlayer() {
    const shelf = document.getElementById('shelf');
    const notchBar = document.getElementById('notchBar');
    const cameraDot = document.getElementById('cameraDot');
    const notchMediaContent = document.getElementById('notchMediaContent');
    const scrollingTitle = document.getElementById('scrollingTitle');
    const mediaPlayer = document.getElementById('mediaPlayer');
    const fileGrid = document.getElementById('fileGrid');
    const shelfHeader = document.getElementById('shelfHeader');

    // Hide scrolling title
    if (scrollingTitle) {
        scrollingTitle.style.opacity = '0';
        scrollingTitle.style.height = '0';
    }

    // Stop marquee
    stopMarqueeAnimation();

    // Reset notch to normal shape (hidden during shelf view)
    if (notchBar) {
        notchBar.style.opacity = '0';
    }
    if (notchMediaContent) notchMediaContent.style.opacity = '0';

    // Show shelf with media player content
    if (shelf) {
        shelf.style.opacity = '1';
        shelf.style.pointerEvents = 'none';
        shelf.style.transform = 'translateX(-50%) scale(1)';
        shelf.style.borderRadius = '0 0 28px 28px';
    }

    // Hide file grid and shelf header, show media player
    if (fileGrid) fileGrid.style.display = 'none';
    if (shelfHeader) shelfHeader.style.display = 'none';
    if (mediaPlayer) {
        mediaPlayer.style.display = 'flex';
        mediaPlayer.style.opacity = '1';
    }

    // Start progress bar and visualizer animation
    animateProgressBar();
    startMediaVisualizerAnimation();

    // After 1s, toggle play/pause (faster)
    demoTimeout = setTimeout(() => {
        if (!demoRunning) return;
        animatePlayPause();

        // After 1.8s more, close and loop (faster)
        demoTimeout = setTimeout(() => {
            if (!demoRunning) return;
            closeMediaDemo();
        }, 1800);
    }, 1000);
}

/**
 * Animate the play/pause button toggle
 */
function animatePlayPause() {
    const playPauseBtn = document.getElementById('playPauseBtn');
    const playIcon = document.getElementById('playIcon');
    const pauseIcon = document.getElementById('pauseIcon');

    if (!playPauseBtn || !playIcon || !pauseIcon) return;

    // Scale down
    playPauseBtn.style.transform = 'scale(0.85)';

    setTimeout(() => {
        // Switch to pause icon
        playIcon.style.display = 'none';
        pauseIcon.style.display = 'block';

        // Scale back up
        playPauseBtn.style.transform = 'scale(1)';
    }, 100);
}

/**
 * Close the media player and loop back to shelf demo
 */
function closeMediaDemo() {
    const shelf = document.getElementById('shelf');
    const notchBar = document.getElementById('notchBar');
    const cameraDot = document.getElementById('cameraDot');
    const mediaPlayer = document.getElementById('mediaPlayer');
    const fileGrid = document.getElementById('fileGrid');
    const notchMediaContent = document.getElementById('notchMediaContent');
    const scrollingTitle = document.getElementById('scrollingTitle');
    const playIcon = document.getElementById('playIcon');
    const pauseIcon = document.getElementById('pauseIcon');
    const shelfHeader = document.getElementById('shelfHeader');

    // Stop all animations
    stopVisualizerAnimation();
    stopMediaVisualizerAnimation();
    stopMarqueeAnimation();

    // Reset notch to normal shape
    if (notchBar) {
        notchBar.style.opacity = '1';
        notchBar.style.borderRadius = '0 0 20px 20px';
        notchBar.style.width = '200px';
    }
    if (cameraDot) cameraDot.style.opacity = '1';
    if (notchMediaContent) notchMediaContent.style.opacity = '0';
    if (scrollingTitle) {
        scrollingTitle.style.opacity = '0';
        scrollingTitle.style.height = '0';
    }

    // Shrink shelf back into notch
    if (shelf) {
        shelf.style.transition = 'all 0.35s cubic-bezier(0.4, 0, 0.2, 1)';
        shelf.style.transform = 'translateX(-50%) scaleX(0.4) scaleY(0.1)';
        shelf.style.opacity = '0';
        shelf.style.borderRadius = '0 0 16px 16px';
    }

    // Reset media player state
    if (mediaPlayer) {
        mediaPlayer.style.display = 'none';
        mediaPlayer.style.opacity = '0';
    }
    if (fileGrid) fileGrid.style.display = 'grid';
    if (shelfHeader) shelfHeader.style.display = 'flex';
    if (playIcon) playIcon.style.display = 'block';
    if (pauseIcon) pauseIcon.style.display = 'none';

    // Reset progress bar
    const progressFill = document.getElementById('mediaProgressFill');
    const currentTime = document.getElementById('currentTime');
    if (progressFill) progressFill.style.width = '4%';
    if (currentTime) currentTime.textContent = '0:07';

    // Reset shelf files for next loop
    resetShelfFiles();

    // Show feature showcase before looping
    demoTimeout = setTimeout(() => {
        if (demoRunning) {
            showFeatureShowcase();
        }
    }, 600);
}

/**
 * Show the feature showcase grid with grow animation from notch
 */
function showFeatureShowcase() {
    const showcase = document.getElementById('featureShowcase');
    if (!showcase) {
        // Fallback: loop directly
        openShelf();
        startShelfDemo();
        return;
    }

    // Show and set initial collapsed state
    showcase.style.display = 'flex';
    showcase.style.opacity = '0';
    showcase.style.transform = 'translateX(-50%) scale(0.4)';

    // Trigger grow animation (like shelf opening)
    requestAnimationFrame(() => {
        showcase.style.opacity = '1';
        showcase.style.transform = 'translateX(-50%) scale(1)';
    });

    // Animate cards with stagger (scale in)
    const cards = showcase.querySelectorAll('.feature-card');
    cards.forEach((card, index) => {
        setTimeout(() => {
            card.style.transition = 'opacity 0.25s ease-out, transform 0.25s ease-out';
            card.style.opacity = '1';
            card.style.transform = 'scale(1)';
        }, 400 + (index * 60));
    });

    // Hold for 2.5s then shrink back and loop
    demoTimeout = setTimeout(() => {
        if (!demoRunning) return;

        // Shrink back into notch (like shelf closing)
        showcase.style.opacity = '0';
        showcase.style.transform = 'translateX(-50%) scale(0.4)';

        setTimeout(() => {
            showcase.style.display = 'none';
            // Reset card states
            cards.forEach(card => {
                card.style.transition = 'none';
                card.style.opacity = '0';
                card.style.transform = 'scale(0.9)';
            });

            // Loop back to shelf
            if (demoRunning) {
                openShelf();
                startShelfDemo();
            }
        }, 500);
    }, 2500);
}

// Visualizer animation state
let visualizerInterval = null;
let mediaVisualizerInterval = null;

/**
 * Start the audio visualizer bar animation (small notch)
 */
function startVisualizerAnimation() {
    const bars = document.querySelectorAll('.visualizer-bar');
    if (bars.length === 0) return;

    visualizerInterval = setInterval(() => {
        bars.forEach((bar) => {
            const minHeight = 4;
            const maxHeight = 16;
            const randomHeight = minHeight + Math.random() * (maxHeight - minHeight);
            bar.style.height = randomHeight + 'px';
        });
    }, 120);
}

/**
 * Stop the small notch visualizer animation
 */
function stopVisualizerAnimation() {
    if (visualizerInterval) {
        clearInterval(visualizerInterval);
        visualizerInterval = null;
    }

    // Reset bars to idle state
    const bars = document.querySelectorAll('.visualizer-bar');
    bars.forEach(bar => {
        bar.style.height = '8px';
    });
}

/**
 * Start the expanded media player visualizer animation
 */
function startMediaVisualizerAnimation() {
    const bars = document.querySelectorAll('.media-visualizer-bar');
    if (bars.length === 0) return;

    mediaVisualizerInterval = setInterval(() => {
        bars.forEach((bar) => {
            const minHeight = 8;
            const maxHeight = 28;
            const randomHeight = minHeight + Math.random() * (maxHeight - minHeight);
            bar.style.height = randomHeight + 'px';
        });
    }, 100);
}

/**
 * Stop the expanded media player visualizer animation
 */
function stopMediaVisualizerAnimation() {
    if (mediaVisualizerInterval) {
        clearInterval(mediaVisualizerInterval);
        mediaVisualizerInterval = null;
    }

    // Reset bars
    const bars = document.querySelectorAll('.media-visualizer-bar');
    const heights = [12, 20, 16, 28, 22, 18];
    bars.forEach((bar, i) => {
        bar.style.height = (heights[i] || 16) + 'px';
    });
}

// Marquee animation state
let marqueeAnimationFrame = null;

/**
 * Start the marquee text scrolling animation
 */
function startMarqueeAnimation() {
    const marqueeText = document.getElementById('marqueeText');
    if (!marqueeText) return;

    let position = 0;
    const speed = 0.8; // pixels per frame

    function animate() {
        position -= speed;

        // Reset when scrolled past
        if (position < -250) {
            position = 100;
        }

        marqueeText.style.transform = `translateX(${position}px)`;
        marqueeAnimationFrame = requestAnimationFrame(animate);
    }

    marqueeAnimationFrame = requestAnimationFrame(animate);
}

/**
 * Stop the marquee animation
 */
function stopMarqueeAnimation() {
    if (marqueeAnimationFrame) {
        cancelAnimationFrame(marqueeAnimationFrame);
        marqueeAnimationFrame = null;
    }

    const marqueeText = document.getElementById('marqueeText');
    if (marqueeText) {
        marqueeText.style.transform = 'translateX(0)';
    }
}

/**
 * Animate the progress bar slowly moving forward
 */
function animateProgressBar() {
    const progressFill = document.getElementById('mediaProgressFill');
    const currentTime = document.getElementById('currentTime');
    if (!progressFill) return;

    // Start at 4% (0:07 of 2:47 = 167 seconds)
    let progress = 4;
    const totalSeconds = 167;

    const progressInterval = setInterval(() => {
        if (!demoRunning || progress >= 15) {
            clearInterval(progressInterval);
            return;
        }

        progress += 0.8;
        progressFill.style.width = progress + '%';

        // Update time display
        if (currentTime) {
            const currentSeconds = Math.floor((progress / 100) * totalSeconds);
            const mins = Math.floor(currentSeconds / 60);
            const secs = currentSeconds % 60;
            currentTime.textContent = `${mins}:${secs.toString().padStart(2, '0')}`;
        }
    }, 250);
}
