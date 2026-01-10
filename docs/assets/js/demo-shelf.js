/**
 * Demo Shelf - Part 1: File selection, context menu, zip creation, rename
 * Handles the notch shelf demo sequence
 */

/**
 * Start the shelf demo sequence (Part 1)
 */
function startShelfDemo() {
    resetShelfFiles();

    // Step 1: Select files one by one (faster)
    demoTimeout = setTimeout(() => {
        if (!demoRunning) return;
        selectFile('file1', 'thumb1', 'name1');

        demoTimeout = setTimeout(() => {
            if (!demoRunning) return;
            selectFile('file2', 'thumb2', 'name2');

            demoTimeout = setTimeout(() => {
                if (!demoRunning) return;
                selectFile('file3', 'thumb3', 'name3');

                // Step 2: Show context menu
                demoTimeout = setTimeout(() => {
                    if (!demoRunning) return;
                    showDemoContextMenu();

                    // Step 3: Highlight Create ZIP
                    demoTimeout = setTimeout(() => {
                        if (!demoRunning) return;
                        highlightCreateZipOption();

                        // Step 4: Click - hide menu, animate files
                        demoTimeout = setTimeout(() => {
                            if (!demoRunning) return;
                            hideDemoContextMenu();
                            animateZip();

                            // Step 5: Show zip result
                            demoTimeout = setTimeout(() => {
                                if (!demoRunning) return;
                                showZipResult();
                            }, 280);
                        }, 350);
                    }, 400);
                }, 400);
            }, 120);
        }, 120);
    }, 350);
}

/**
 * Select a file with blue highlight
 */
function selectFile(fileId, thumbId, nameId) {
    const thumb = document.getElementById(thumbId);
    const name = document.getElementById(nameId);
    if (thumb) {
        thumb.style.boxShadow = '0 0 0 2px rgb(59, 130, 246)';
        thumb.style.backgroundColor = 'rgba(59, 130, 246, 0.3)';
    }
    if (name) {
        name.style.backgroundColor = 'rgb(59, 130, 246)';
        name.style.color = 'white';
        name.style.fontWeight = '700';
    }
}

/**
 * Show context menu positioned over shelf
 */
function showDemoContextMenu() {
    const shelfEl = document.getElementById('shelf');
    const shelfRect = shelfEl.getBoundingClientRect();
    document.getElementById('contextFileName').textContent = '3 items selected';
    contextMenu.style.left = (shelfRect.left + shelfRect.width / 2) + 'px';
    contextMenu.style.top = (shelfRect.top + 180) + 'px';
    contextMenu.style.opacity = '1';
    contextMenu.style.transform = 'scale(1)';
}

/**
 * Highlight the Create ZIP button
 */
function highlightCreateZipOption() {
    const createZipBtn = document.getElementById('createZipBtn');
    if (createZipBtn) {
        createZipBtn.style.backgroundColor = 'rgba(255, 255, 255, 0.15)';
    }
}

/**
 * Hide context menu
 */
function hideDemoContextMenu() {
    contextMenu.style.opacity = '0';
    contextMenu.style.transform = 'scale(0.95)';
    const createZipBtn = document.getElementById('createZipBtn');
    if (createZipBtn) {
        createZipBtn.style.backgroundColor = '';
    }
}

/**
 * Animate files merging into ZIP
 */
function animateZip() {
    const files = document.querySelectorAll('.shelf-file');
    files.forEach((file, i) => {
        file.style.transition = 'all 0.4s ease-out';
        file.style.transform = 'scale(0.5) translateX(' + (i - 1) * -50 + 'px)';
        file.style.opacity = '0.5';
    });
}

/**
 * Show the ZIP file result and trigger rename animation
 */
function showZipResult() {
    const fileGrid = document.getElementById('fileGrid');
    document.getElementById('itemCount').textContent = '1 item';
    fileGrid.innerHTML = `
        <div id="zipFile" class="shelf-file col-span-3 flex flex-col items-center p-2 rounded-2xl transition-all duration-200" style="animation: scaleIn 0.3s ease-out;">
            <div class="w-[60px] h-[60px] rounded-2xl bg-white/10 flex items-center justify-center mb-1.5" style="box-shadow: 0 0 0 2px rgb(59, 130, 246); background-color: rgba(59, 130, 246, 0.3);">
                <div class="w-11 h-11 rounded-[14px] bg-gradient-to-br from-stone-400 to-stone-600 flex items-center justify-center shadow-lg">
                    <svg class="w-6 h-6 text-white" fill="currentColor" viewBox="0 0 20 20">
                        <path fill-rule="evenodd" d="M4 4a2 2 0 012-2h4.586A2 2 0 0112 2.586L15.414 6A2 2 0 0116 7.414V16a2 2 0 01-2 2H6a2 2 0 01-2-2V4z" clip-rule="evenodd"/>
                    </svg>
                </div>
            </div>
            <p id="zipName" class="bg-blue-500 text-white text-[10px] font-bold px-2 py-0.5 rounded transition-all duration-300">Archive.zip</p>
            <p class="text-white/40 text-[10px]">3 items • 2.6 MB</p>
        </div>
    `;

    // Step 6: Show rename animation (quicker)
    demoTimeout = setTimeout(() => {
        if (!demoRunning) return;
        showRenameAnimation();
    }, 500);
}

/**
 * Show rename animation with typing effect
 */
function showRenameAnimation() {
    const zipName = document.getElementById('zipName');
    if (!zipName) return;

    // Show rename field with dotted border
    zipName.style.background = 'rgba(0,0,0,0.3)';
    zipName.style.border = '1.5px dashed rgba(59, 130, 246, 0.8)';
    zipName.style.animation = 'none';
    zipName.innerHTML = '<span class="animate-pulse">|</span>';

    // Type out "Hello!" character by character
    const targetText = 'Hello!';
    let currentIndex = 0;

    const typeInterval = setInterval(() => {
        if (!demoRunning || currentIndex >= targetText.length) {
            clearInterval(typeInterval);
            if (demoRunning) {
                // Finalize the rename
                demoTimeout = setTimeout(() => {
                    if (!demoRunning) return;
                    zipName.style.background = 'rgb(59, 130, 246)';
                    zipName.style.border = 'none';
                    zipName.textContent = 'Hello!.zip';

                    // Transition to Part 2: Basket demo (quicker)
                    demoTimeout = setTimeout(() => {
                        if (!demoRunning) return;
                        startBasketDemo(); // Hand off to basket demo
                    }, 550);
                }, 300);
            }
            return;
        }
        currentIndex++;
        zipName.innerHTML = targetText.substring(0, currentIndex) + '<span class="animate-pulse">|</span>';
    }, 100);
}

/**
 * Reset shelf files to original state
 */
function resetShelfFiles() {
    const fileGrid = document.getElementById('fileGrid');
    fileGrid.innerHTML = `
        <div id="file1" class="shelf-file flex flex-col items-center p-1 rounded-2xl transition-all duration-200">
            <div id="thumb1" class="w-[60px] h-[60px] rounded-2xl bg-white/10 flex items-center justify-center mb-1.5 transition-all duration-200">
                <div class="w-11 h-11 rounded-[14px] bg-gradient-to-br from-sky-400 to-blue-600 flex items-center justify-center shadow-lg">
                    <svg class="w-6 h-6 text-white" fill="currentColor" viewBox="0 0 20 20">
                        <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd"/>
                    </svg>
                </div>
            </div>
            <p id="name1" class="text-white/85 text-[10px] font-medium truncate w-[68px] text-center px-1 py-0.5 rounded transition-all duration-200">photo.jpg</p>
            <p class="text-white/40 text-[10px]">2.4 MB</p>
        </div>
        <div id="file2" class="shelf-file flex flex-col items-center p-1 rounded-2xl transition-all duration-200">
            <div id="thumb2" class="w-[60px] h-[60px] rounded-2xl bg-white/10 flex items-center justify-center mb-1.5 transition-all duration-200">
                <div class="w-11 h-11 rounded-[14px] bg-gradient-to-br from-red-400 to-red-600 flex items-center justify-center shadow-lg">
                    <svg class="w-6 h-6 text-white" fill="currentColor" viewBox="0 0 20 20">
                        <path fill-rule="evenodd" d="M4 4a2 2 0 012-2h4.586A2 2 0 0112 2.586L15.414 6A2 2 0 0116 7.414V16a2 2 0 01-2 2H6a2 2 0 01-2-2V4z" clip-rule="evenodd"/>
                    </svg>
                </div>
            </div>
            <p id="name2" class="text-white/85 text-[10px] font-medium truncate w-[68px] text-center px-1 py-0.5 rounded transition-all duration-200">document.pdf</p>
            <p class="text-white/40 text-[10px]">156 KB</p>
        </div>
        <div id="file3" class="shelf-file flex flex-col items-center p-1 rounded-2xl transition-all duration-200">
            <div id="thumb3" class="w-[60px] h-[60px] rounded-2xl bg-white/10 flex items-center justify-center mb-1.5 transition-all duration-200">
                <div class="w-11 h-11 rounded-[14px] bg-gradient-to-br from-amber-400 to-orange-500 flex items-center justify-center shadow-lg">
                    <svg class="w-6 h-6 text-white" fill="currentColor" viewBox="0 0 20 20">
                        <path d="M2 6a2 2 0 012-2h5l2 2h5a2 2 0 012 2v6a2 2 0 01-2 2H4a2 2 0 01-2-2V6z"/>
                    </svg>
                </div>
            </div>
            <p id="name3" class="text-white/85 text-[10px] font-medium truncate w-[68px] text-center px-1 py-0.5 rounded transition-all duration-200">project/</p>
            <p class="text-white/40 text-[10px]">12 items</p>
        </div>
    `;
    document.getElementById('itemCount').textContent = '3 items';
    hideDemoContextMenu();
}
