document.addEventListener('DOMContentLoaded', () => {
    const el = {
        notch: document.getElementById('notch'),
        notchDropZone: document.getElementById('notchDropZone'),
        notchQueue: document.getElementById('notchQueue'),
        mediaPlayToggle: document.getElementById('mediaPlayToggle'),
        mediaScrubber: document.getElementById('mediaScrubber'),
        menubarClock: document.getElementById('menubarClock'),
        menuBarState: document.getElementById('menuBarState'),
        finderFiles: document.getElementById('finderFiles'),
        basketDropZone: document.getElementById('basketDropZone'),
        basketItems: document.getElementById('basketItems'),
        jiggleSummon: document.getElementById('jiggleSummon'),
        clipboardInput: document.getElementById('clipboardInput'),
        saveClipboard: document.getElementById('saveClipboard'),
        clipboardItems: document.getElementById('clipboardItems'),
        toolRow: document.getElementById('toolRow'),
        editorCanvas: document.getElementById('editorCanvas'),
        editorLayer: document.getElementById('editorLayer'),
        clearStamps: document.getElementById('clearStamps'),
        stepList: document.getElementById('stepList'),
        stepDescription: document.getElementById('stepDescription'),
        nextStep: document.getElementById('nextStep'),
        resetDemo: document.getElementById('resetDemo'),
        tapCallout: document.getElementById('tapCallout'),
        settingsStatus: document.getElementById('settingsStatus')
    };

    const steps = [
        {
            target: 'notch',
            text: 'Step 1: Hover the notch to expand the media HUD and file action zone.',
            onEnter: () => expandNotch()
        },
        {
            target: 'finderWindow',
            text: 'Step 2: Drag a file card from Finder. Those are real draggable demo files.',
            onEnter: () => collapseNotchIfAllowed()
        },
        {
            target: 'notchDropZone',
            text: 'Step 3: Drop the file on the notch, then run Unzip or Convert from native-style action buttons.',
            onEnter: () => {
                state.notchPinned = true;
                expandNotch();
            }
        },
        {
            target: 'basketWindow',
            text: 'Step 4: Tap Jiggle to summon floating basket behavior and stage files there.',
            onEnter: () => collapseNotchIfAllowed()
        },
        {
            target: 'clipboardWindow',
            text: 'Step 5: Save text snippets and pin favorites in the clipboard manager.',
            onEnter: () => collapseNotchIfAllowed()
        },
        {
            target: 'screenshotWindow',
            text: 'Step 6: Pick a screenshot tool and click the canvas to stamp highlights, blur, redact, or arrows.',
            onEnter: () => collapseNotchIfAllowed()
        },
        {
            target: 'menuFloatBar',
            text: 'Step 7: Toggle live menu bar manager items in the floating bar.',
            onEnter: () => collapseNotchIfAllowed()
        },
        {
            target: 'extensionsWindow',
            text: 'Step 8: Enable or disable extensions directly from the showcase window.',
            onEnter: () => collapseNotchIfAllowed()
        },
        {
            target: 'settingsWindow',
            text: 'Step 9: Switch tabs and toggles in settings to configure Droppy behavior.',
            onEnter: () => collapseNotchIfAllowed()
        }
    ];

    const baseClipboard = [
        { id: uid(), text: 'The native productivity layer MacOS is missing', pinned: true, time: nowTag() },
        { id: uid(), text: 'droppy://extensions/menu-bar-manager', pinned: false, time: nowTag() }
    ];

    const baseBasket = [
        { id: uid(), name: 'Moodboard.heic', meta: 'Staged' }
    ];

    const state = {
        notchPinned: false,
        notchQueue: [],
        basket: [...baseBasket],
        clipboard: [...baseClipboard],
        activeTool: 'highlight',
        activeStep: 0,
        mediaPlaying: true,
        activeCalloutTarget: null
    };

    function uid() {
        return Math.random().toString(16).slice(2);
    }

    function nowTag() {
        return new Intl.DateTimeFormat('en-US', {
            hour: 'numeric',
            minute: '2-digit'
        }).format(new Date());
    }

    function updateClock() {
        if (!el.menubarClock) return;
        el.menubarClock.textContent = new Intl.DateTimeFormat('en-US', {
            weekday: 'short',
            hour: 'numeric',
            minute: '2-digit'
        }).format(new Date());
    }

    function expandNotch() {
        el.notch?.classList.add('is-expanded');
    }

    function collapseNotch() {
        el.notch?.classList.remove('is-expanded');
    }

    function collapseNotchIfAllowed() {
        if (!state.notchPinned) collapseNotch();
    }

    function renderNotchQueue() {
        if (!el.notchQueue) return;
        if (!state.notchQueue.length) {
            el.notchQueue.innerHTML = '<li><span>No queued files yet</span><small>Drop a file into the notch</small></li>';
            return;
        }

        el.notchQueue.innerHTML = state.notchQueue
            .map((item) => `<li><span>${escapeHtml(item.name)}</span><small>${escapeHtml(item.status)}</small></li>`)
            .join('');
    }

    function renderBasketItems() {
        if (!el.basketItems) return;
        if (!state.basket.length) {
            el.basketItems.innerHTML = '<li><span>Basket is empty</span><small>Drop files to stage</small></li>';
            return;
        }

        el.basketItems.innerHTML = state.basket
            .map((item) => `<li><span>${escapeHtml(item.name)}</span><small>${escapeHtml(item.meta)}</small></li>`)
            .join('');
    }

    function sortClipboard() {
        state.clipboard.sort((a, b) => Number(b.pinned) - Number(a.pinned));
    }

    function renderClipboard() {
        if (!el.clipboardItems) return;
        sortClipboard();

        el.clipboardItems.innerHTML = state.clipboard
            .map((item) => {
                const pinLabel = item.pinned ? 'Unpin' : 'Pin';
                return `
                    <li>
                        <div>
                            <div class="clip-text">${escapeHtml(item.text)}</div>
                            <div class="clip-meta">${escapeHtml(item.time)}</div>
                        </div>
                        <button class="tiny-btn" data-pin-id="${item.id}">${pinLabel}</button>
                    </li>
                `;
            })
            .join('');
    }

    function addClipboardItem(text) {
        const trimmed = text.trim();
        if (!trimmed) return;
        state.clipboard.unshift({
            id: uid(),
            text: trimmed,
            pinned: false,
            time: nowTag()
        });
        renderClipboard();
    }

    function addFileToBasket(name, meta) {
        state.basket.unshift({ id: uid(), name, meta });
        state.basket = state.basket.slice(0, 8);
        renderBasketItems();
    }

    function queueFile(file) {
        state.notchQueue.unshift({
            id: uid(),
            name: file.name,
            size: file.size || '—',
            status: 'Queued'
        });
        state.notchQueue = state.notchQueue.slice(0, 6);
        renderNotchQueue();
    }

    function dropTargetEvents(target, onDrop) {
        if (!target) return;

        target.addEventListener('dragover', (event) => {
            event.preventDefault();
            target.classList.add('is-drag-over');
        });

        target.addEventListener('dragleave', () => {
            target.classList.remove('is-drag-over');
        });

        target.addEventListener('drop', (event) => {
            event.preventDefault();
            target.classList.remove('is-drag-over');
            const raw = event.dataTransfer?.getData('text/plain');
            if (!raw) return;
            try {
                const file = JSON.parse(raw);
                onDrop(file);
            } catch (error) {
                console.error('Invalid dropped payload', error);
            }
        });
    }

    function setTool(tool) {
        state.activeTool = tool;
        el.toolRow?.querySelectorAll('[data-tool]').forEach((button) => {
            button.classList.toggle('is-active', button.dataset.tool === tool);
        });
    }

    function addStampAt(x, y) {
        if (!el.editorLayer) return;
        const stamp = document.createElement('div');
        stamp.className = `stamp ${state.activeTool}`;
        stamp.style.left = `${x}px`;
        stamp.style.top = `${y}px`;
        el.editorLayer.appendChild(stamp);
    }

    function updateMenuBarState() {
        const onMenu = document.querySelectorAll('.menu-float-item.is-on').length;
        const onExtensions = document.querySelectorAll('.extension-chip.is-on').length;
        const total = onMenu + onExtensions;
        if (el.menuBarState) {
            el.menuBarState.textContent = `${total} extensions active`;
        }
    }

    function escapeHtml(text) {
        return String(text)
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;')
            .replaceAll('"', '&quot;')
            .replaceAll("'", '&#39;');
    }

    function actionLabel(action) {
        if (action === 'unzip') return 'Unzipped';
        if (action === 'convert') return 'Converted';
        return 'Compressed';
    }

    function transformedName(action, sourceName) {
        if (action === 'unzip') return sourceName.replace(/\.zip$/i, '') || `${sourceName}-folder`;
        if (action === 'convert') return sourceName.replace(/\.[^.]+$/, '.webp');
        return sourceName.endsWith('.zip') ? sourceName : `${sourceName}.zip`;
    }

    function runNotchAction(action) {
        if (!state.notchQueue.length) {
            addClipboardItem(`No file queued for ${action}`);
            return;
        }

        const file = state.notchQueue[0];
        file.status = `${actionLabel(action)}...`;
        renderNotchQueue();

        window.setTimeout(() => {
            const output = transformedName(action, file.name);
            file.name = output;
            file.status = `${actionLabel(action)} complete`;
            renderNotchQueue();
            addFileToBasket(output, actionLabel(action));
            addClipboardItem(`${actionLabel(action)} ${output}`);
        }, 650);
    }

    function focusStep(index) {
        state.activeStep = (index + steps.length) % steps.length;
        const step = steps[state.activeStep];

        el.stepList?.querySelectorAll('.step-btn').forEach((button, idx) => {
            button.classList.toggle('is-active', idx === state.activeStep);
        });

        if (el.stepDescription) {
            el.stepDescription.textContent = step.text;
        }

        document.querySelectorAll('.mac-window, .notch, .notch-panel').forEach((node) => {
            node.classList.remove('is-focus');
        });

        const target = document.getElementById(step.target);
        if (target) {
            target.classList.add('is-focus');
            state.activeCalloutTarget = target;
            placeCallout(target);
        }

        step.onEnter?.();
    }

    function placeCallout(target) {
        if (!el.tapCallout || !target) return;
        const rect = target.getBoundingClientRect();
        const callout = el.tapCallout;
        let top = rect.top - 38;

        if (top < 44) {
            top = rect.bottom + 10;
        }

        const left = Math.min(window.innerWidth - 90, Math.max(56, rect.left + rect.width / 2));

        callout.style.top = `${top}px`;
        callout.style.left = `${left}px`;
        callout.style.transform = 'translateX(-50%)';
        callout.classList.add('is-visible');
    }

    function resetDemo() {
        state.notchPinned = false;
        state.notchQueue = [];
        state.basket = [...baseBasket];
        state.clipboard = [...baseClipboard];
        state.activeTool = 'highlight';
        state.mediaPlaying = true;

        renderNotchQueue();
        renderBasketItems();
        renderClipboard();
        setTool('highlight');

        if (el.editorLayer) el.editorLayer.innerHTML = '';
        if (el.mediaPlayToggle) el.mediaPlayToggle.textContent = 'Pause';
        if (el.mediaScrubber) el.mediaScrubber.value = '34';

        collapseNotch();
        focusStep(0);
        updateMenuBarState();

        if (el.settingsStatus) {
            el.settingsStatus.textContent = 'Settings synced • native mode enabled.';
        }
    }

    el.notch?.addEventListener('mouseenter', expandNotch);

    el.notch?.addEventListener('mouseleave', () => {
        window.setTimeout(() => {
            if (!state.notchPinned) collapseNotch();
        }, 120);
    });

    el.notch?.addEventListener('click', () => {
        state.notchPinned = !state.notchPinned;
        if (state.notchPinned) {
            expandNotch();
        } else {
            collapseNotch();
        }
    });

    document.querySelectorAll('.finder-file').forEach((fileEl) => {
        fileEl.addEventListener('dragstart', (event) => {
            const payload = fileEl.dataset.file;
            if (!payload) return;
            event.dataTransfer?.setData('text/plain', payload);
            event.dataTransfer.effectAllowed = 'copy';
        });
    });

    dropTargetEvents(el.notchDropZone, (file) => {
        state.notchPinned = true;
        queueFile(file);
        expandNotch();
    });

    dropTargetEvents(el.basketDropZone, (file) => {
        addFileToBasket(file.name, 'Staged');
    });

    document.querySelectorAll('[data-file-action]').forEach((button) => {
        button.addEventListener('click', (event) => {
            event.stopPropagation();
            const action = button.getAttribute('data-file-action');
            if (!action) return;
            runNotchAction(action);
        });
    });

    document.querySelectorAll('.copy-snippet').forEach((button) => {
        button.addEventListener('click', () => {
            const value = button.getAttribute('data-copy') || '';
            addClipboardItem(value);
            if (navigator.clipboard && value) {
                navigator.clipboard.writeText(value).catch(() => {
                    // Ignore clipboard permission failures in demo mode.
                });
            }
        });
    });

    el.saveClipboard?.addEventListener('click', () => {
        if (!el.clipboardInput) return;
        addClipboardItem(el.clipboardInput.value);
        el.clipboardInput.select();
    });

    el.clipboardInput?.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') {
            event.preventDefault();
            el.saveClipboard?.click();
        }
    });

    el.clipboardItems?.addEventListener('click', (event) => {
        const target = event.target;
        if (!(target instanceof HTMLElement)) return;
        const id = target.getAttribute('data-pin-id');
        if (!id) return;
        const item = state.clipboard.find((entry) => entry.id === id);
        if (!item) return;
        item.pinned = !item.pinned;
        renderClipboard();
    });

    el.jiggleSummon?.addEventListener('click', () => {
        const basketWindow = document.getElementById('basketWindow');
        if (!basketWindow) return;
        basketWindow.classList.add('is-jiggle');
        window.setTimeout(() => basketWindow.classList.remove('is-jiggle'), 550);
        addClipboardItem('Floating basket summoned');
    });

    el.toolRow?.addEventListener('click', (event) => {
        const target = event.target;
        if (!(target instanceof HTMLElement)) return;
        const tool = target.getAttribute('data-tool');
        if (!tool) return;
        setTool(tool);
    });

    el.editorCanvas?.addEventListener('click', (event) => {
        const rect = el.editorCanvas.getBoundingClientRect();
        addStampAt(event.clientX - rect.left, event.clientY - rect.top);
    });

    el.clearStamps?.addEventListener('click', () => {
        if (el.editorLayer) {
            el.editorLayer.innerHTML = '';
        }
    });

    document.querySelectorAll('.menu-float-item, .extension-chip').forEach((node) => {
        node.addEventListener('click', () => {
            node.classList.toggle('is-on');
            updateMenuBarState();
        });
    });

    document.querySelectorAll('.tab-btn').forEach((tab) => {
        tab.addEventListener('click', () => {
            document.querySelectorAll('.tab-btn').forEach((node) => node.classList.remove('is-active'));
            tab.classList.add('is-active');
            if (el.settingsStatus) {
                el.settingsStatus.textContent = `Viewing ${tab.textContent?.trim() || 'General'} settings.`;
            }
        });
    });

    document.querySelectorAll('.setting-row input[type="checkbox"]').forEach((toggle) => {
        toggle.addEventListener('change', () => {
            if (el.settingsStatus) {
                el.settingsStatus.textContent = 'Settings synced • profile updated instantly.';
            }
        });
    });

    el.stepList?.addEventListener('click', (event) => {
        const target = event.target;
        if (!(target instanceof HTMLElement)) return;
        const step = target.getAttribute('data-step');
        if (step === null) return;
        focusStep(Number(step));
    });

    el.nextStep?.addEventListener('click', () => {
        focusStep(state.activeStep + 1);
    });

    el.resetDemo?.addEventListener('click', resetDemo);

    window.addEventListener('resize', () => {
        if (state.activeCalloutTarget) {
            placeCallout(state.activeCalloutTarget);
        }
    });

    window.addEventListener('scroll', () => {
        if (state.activeCalloutTarget) {
            placeCallout(state.activeCalloutTarget);
        }
    }, { passive: true });

    el.mediaPlayToggle?.addEventListener('click', (event) => {
        event.stopPropagation();
        state.mediaPlaying = !state.mediaPlaying;
        el.mediaPlayToggle.textContent = state.mediaPlaying ? 'Pause' : 'Play';
    });

    window.setInterval(() => {
        if (!state.mediaPlaying || !el.mediaScrubber) return;
        const nextValue = (Number(el.mediaScrubber.value) + 1) % 101;
        el.mediaScrubber.value = String(nextValue);
    }, 950);

    updateClock();
    window.setInterval(updateClock, 15_000);

    renderNotchQueue();
    renderBasketItems();
    renderClipboard();
    setTool('highlight');
    focusStep(0);
    updateMenuBarState();
});
