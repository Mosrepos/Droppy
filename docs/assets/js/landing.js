(() => {
    const data = window.DROPPY_LANDING_DATA;
    if (!data) {
        console.error('DROPPY_LANDING_DATA is missing.');
        return;
    }

    const state = {
        activeCategory: 'all',
        query: '',
        installCounts: {},
        currentExtension: null
    };

    const els = {
        nativeGrid: document.getElementById('native-layer-grid'),
        coreStack: document.getElementById('core-feature-list'),
        extensionChips: document.getElementById('extension-chip-list'),
        extensionGrid: document.getElementById('extensions-grid'),
        extensionStatsStatus: document.getElementById('extension-stats-status'),
        retryExtensionStats: document.getElementById('retry-extension-stats'),
        extensionSearch: document.getElementById('extension-search'),
        downloadModal: document.getElementById('download-modal'),
        extensionModal: document.getElementById('extension-modal'),
        stickyCta: document.getElementById('sticky-cta'),
        directDownloadButtons: Array.from(document.querySelectorAll('[data-direct-download]')),
        downloadStatus: document.getElementById('download-status'),
        retryDmg: document.getElementById('retry-dmg'),
        navLinks: Array.from(document.querySelectorAll('[data-nav-link]')),
        openDownloadButtons: Array.from(document.querySelectorAll('[data-open-download]')),
        closeDownloadModal: document.getElementById('close-download-modal'),
        closeExtensionModal: document.getElementById('close-extension-modal')
    };

    const extensionModalNodes = {
        icon: document.getElementById('extension-modal-icon'),
        title: document.getElementById('extension-modal-title'),
        category: document.getElementById('extension-modal-category'),
        installs: document.getElementById('extension-modal-installs'),
        description: document.getElementById('extension-modal-description'),
        screenshot: document.getElementById('extension-modal-screenshot'),
        features: document.getElementById('extension-modal-features'),
        deepLink: document.getElementById('extension-modal-link')
    };

    function escapeHtml(text) {
        return String(text)
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;')
            .replaceAll('"', '&quot;')
            .replaceAll("'", '&#039;');
    }

    function setStatus(row, rowState, message, withRetryButton) {
        if (!row) return;
        row.dataset.state = rowState;
        const textNode = row.querySelector('[data-status-text]');
        if (textNode) textNode.textContent = message;
        const retryNode = row.querySelector('[data-status-retry]');
        if (retryNode) retryNode.style.display = withRetryButton ? 'inline-flex' : 'none';
    }

    function renderNativeLayer() {
        if (!els.nativeGrid) return;
        els.nativeGrid.innerHTML = data.nativeLayerClusters.map((cluster) => {
            const items = cluster.items.map((item) => `<li>${escapeHtml(item)}</li>`).join('');
            return `
                <article class="native-card glass reveal">
                    <h3>${escapeHtml(cluster.title)}</h3>
                    <p>${escapeHtml(cluster.description)}</p>
                    <ul>${items}</ul>
                </article>
            `;
        }).join('');
    }

    function renderCoreFeatures() {
        if (!els.coreStack) return;
        els.coreStack.innerHTML = data.coreFeatureBlocks.map((feature, index) => {
            const bulletMarkup = feature.bullets.map((bullet) => `
                <li>
                    <h4>${escapeHtml(bullet.title)}</h4>
                    <p>${escapeHtml(bullet.text)}</p>
                </li>
            `).join('');

            return `
                <article class="feature-card glass reveal" id="${escapeHtml(feature.id)}">
                    <div class="feature-grid" style="direction:${index % 2 === 1 ? 'rtl' : 'ltr'};">
                        <div class="feature-meta" style="direction:ltr;">
                            <p class="eyebrow">${escapeHtml(feature.eyebrow)}</p>
                            <h3>${escapeHtml(feature.title)}</h3>
                            <p>${escapeHtml(feature.description)}</p>
                            <ul class="feature-bullets">${bulletMarkup}</ul>
                        </div>
                        <div class="feature-media" style="direction:ltr;">
                            <img src="${escapeHtml(feature.image)}" alt="${escapeHtml(feature.title)}">
                        </div>
                    </div>
                </article>
            `;
        }).join('');
    }

    function extensionMatchesFilter(extension) {
        const query = state.query.trim().toLowerCase();
        const inCategory = state.activeCategory === 'all' || extension.category === state.activeCategory;
        if (!inCategory) return false;
        if (!query) return true;

        const searchSource = [
            extension.title,
            extension.category,
            extension.categoryLabel,
            extension.description,
            ...(extension.tags || [])
        ].join(' ').toLowerCase();

        return searchSource.includes(query);
    }

    function getExtensionStats(extensionId) {
        const analyticsId = data.extensionIdMap[extensionId];
        return analyticsId ? (state.installCounts[analyticsId] || 0) : 0;
    }

    function renderExtensions() {
        if (!els.extensionGrid) return;
        const visible = data.extensions.filter(extensionMatchesFilter);

        if (visible.length === 0) {
            els.extensionGrid.innerHTML = `
                <article class="extension-card">
                    <p class="extension-desc" style="min-height:0;">No extensions match your current filter.</p>
                </article>
            `;
            return;
        }

        els.extensionGrid.innerHTML = visible.map((extension) => {
            const installs = getExtensionStats(extension.id);
            const tags = (extension.tags || []).map((tag) => `<span class="extension-tag">${escapeHtml(tag)}</span>`).join('');

            return `
                <article class="extension-card reveal" data-extension-id="${escapeHtml(extension.id)}" tabindex="0" role="button">
                    <div class="extension-head">
                        <img src="${escapeHtml(extension.icon)}" alt="${escapeHtml(extension.title)}">
                        <div>
                            <h3>${escapeHtml(extension.title)}</h3>
                            <span>${escapeHtml(extension.categoryLabel)}</span>
                        </div>
                    </div>
                    <p class="extension-desc">${escapeHtml(extension.description)}</p>
                    <div class="extension-stats">
                        <span><strong data-install-count="${escapeHtml(extension.id)}">${installs.toLocaleString()}</strong> installs</span>
                    </div>
                    <div class="extension-tags">${tags}</div>
                </article>
            `;
        }).join('');

        bindExtensionCardEvents();
        observeRevealElements();
    }

    function renderExtensionChips() {
        if (!els.extensionChips) return;
        els.extensionChips.innerHTML = data.extensionCategories.map((category) => {
            const isActive = category.id === state.activeCategory;
            return `<button class="chip ${isActive ? 'is-active' : ''}" data-category-chip="${escapeHtml(category.id)}">${escapeHtml(category.label)}</button>`;
        }).join('');

        els.extensionChips.querySelectorAll('[data-category-chip]').forEach((chip) => {
            chip.addEventListener('click', () => {
                state.activeCategory = chip.dataset.categoryChip || 'all';
                renderExtensionChips();
                renderExtensions();
            });
        });
    }

    function bindExtensionCardEvents() {
        if (!els.extensionGrid) return;
        const openById = (id) => openExtensionModal(id);
        els.extensionGrid.querySelectorAll('[data-extension-id]').forEach((card) => {
            card.addEventListener('click', () => openById(card.dataset.extensionId));
            card.addEventListener('keydown', (event) => {
                if (event.key === 'Enter' || event.key === ' ') {
                    event.preventDefault();
                    openById(card.dataset.extensionId);
                }
            });
        });
    }

    function updateStatsUI() {
        data.extensions.forEach((extension) => {
            const count = getExtensionStats(extension.id);

            document.querySelectorAll(`[data-install-count="${extension.id}"]`).forEach((node) => {
                node.textContent = count.toLocaleString();
            });
        });

        if (state.currentExtension) {
            openExtensionModal(state.currentExtension, true);
        }
    }

    async function fetchExtensionStats() {
        setStatus(els.extensionStatsStatus, 'loading', 'Loading live extension stats...', false);

        try {
            const sharedHeaders = {
                apikey: data.SUPABASE_ANON_KEY,
                'Content-Type': 'application/json',
                Authorization: `Bearer ${data.SUPABASE_ANON_KEY}`
            };

            const countsRes = await fetch(`${data.SUPABASE_URL}/rest/v1/rpc/get_extension_counts`, {
                method: 'POST',
                headers: sharedHeaders
            });

            if (!countsRes.ok) {
                throw new Error(`Counts: ${countsRes.status}`);
            }

            const counts = await countsRes.json();

            if (!Array.isArray(counts)) {
                throw new Error('Unexpected response shape while loading stats.');
            }

            state.installCounts = {};

            counts.forEach((row) => {
                if (row && row.extension_id) state.installCounts[row.extension_id] = Number(row.install_count || 0);
            });

            updateStatsUI();
            setStatus(els.extensionStatsStatus, 'success', 'Live stats updated.', false);
        } catch (error) {
            console.error('Failed to load extension stats:', error);
            setStatus(els.extensionStatsStatus, 'error', 'Could not load extension stats. Retry when your connection is back.', true);
        }
    }

    function openExtensionModal(extensionId, skipOpen = false) {
        const extension = data.extensions.find((item) => item.id === extensionId);
        if (!extension || !els.extensionModal) return;

        const count = getExtensionStats(extension.id);
        state.currentExtension = extension.id;

        extensionModalNodes.icon.src = extension.icon;
        extensionModalNodes.icon.alt = extension.title;
        extensionModalNodes.title.textContent = extension.title;
        extensionModalNodes.category.textContent = extension.categoryLabel;
        extensionModalNodes.installs.textContent = count.toLocaleString();
        extensionModalNodes.description.textContent = extension.description;
        extensionModalNodes.deepLink.href = extension.deepUrl;

        extensionModalNodes.features.innerHTML = extension.features
            .map((feature) => `<li>${escapeHtml(feature)}</li>`)
            .join('');

        if (extension.screenshot) {
            extensionModalNodes.screenshot.src = extension.screenshot;
            extensionModalNodes.screenshot.style.display = 'block';
        } else {
            extensionModalNodes.screenshot.removeAttribute('src');
            extensionModalNodes.screenshot.style.display = 'none';
        }

        if (!skipOpen) {
            els.extensionModal.classList.add('is-active');
            document.body.style.overflow = 'hidden';
        }
    }

    function closeExtensionModal() {
        if (!els.extensionModal) return;
        els.extensionModal.classList.remove('is-active');
        state.currentExtension = null;
        releaseBodyLockIfNeeded();
    }

    function openDownloadModal() {
        if (!els.downloadModal) return;
        els.downloadModal.classList.add('is-active');
        document.body.style.overflow = 'hidden';
    }

    function closeDownloadModal() {
        if (!els.downloadModal) return;
        els.downloadModal.classList.remove('is-active');
        releaseBodyLockIfNeeded();
    }

    function releaseBodyLockIfNeeded() {
        const anyModalOpen = (els.extensionModal && els.extensionModal.classList.contains('is-active')) ||
            (els.downloadModal && els.downloadModal.classList.contains('is-active'));
        if (!anyModalOpen) {
            document.body.style.overflow = '';
        }
    }

    function setDownloadStatus(stateName, message, withRetry) {
        if (!els.downloadStatus) return;
        els.downloadStatus.dataset.state = stateName;
        els.downloadStatus.textContent = message;
        if (els.retryDmg) {
            els.retryDmg.style.display = withRetry ? 'inline-flex' : 'none';
        }
    }

    async function resolveDirectDmgUrl() {
        setDownloadStatus('loading', 'Resolving latest DMG from GitHub...', false);

        try {
            const res = await fetch('https://api.github.com/repos/iordv/Droppy/releases/latest');
            if (!res.ok) {
                throw new Error(`GitHub API request failed with status ${res.status}`);
            }

            const release = await res.json();
            const dmg = (release.assets || []).find((asset) => typeof asset.name === 'string' && asset.name.endsWith('.dmg'));
            if (!dmg || !dmg.browser_download_url) {
                throw new Error('Latest release does not contain a DMG asset.');
            }

            els.directDownloadButtons.forEach((button) => {
                button.href = dmg.browser_download_url;
            });

            setDownloadStatus('success', 'Latest DMG is ready to download.', false);
        } catch (error) {
            console.error('Failed to resolve DMG:', error);
            setDownloadStatus('error', 'Could not resolve latest DMG. Retry to fetch the direct download link.', true);
        }
    }

    function initNavTracking() {
        if (!els.navLinks.length) return;

        const sectionMap = new Map();
        els.navLinks.forEach((link) => {
            const href = link.getAttribute('href');
            if (!href || !href.startsWith('#')) return;
            const section = document.querySelector(href);
            if (section) sectionMap.set(section, link);
        });

        const observer = new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
                if (!entry.isIntersecting) return;
                const link = sectionMap.get(entry.target);
                if (!link) return;

                els.navLinks.forEach((item) => item.classList.remove('is-active'));
                link.classList.add('is-active');
            });
        }, {
            threshold: 0.38,
            rootMargin: '-20% 0px -45% 0px'
        });

        sectionMap.forEach((_, section) => observer.observe(section));
    }

    function initStickyCta() {
        const topSection = document.getElementById('top');
        if (!topSection || !els.stickyCta) return;

        const observer = new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
                if (entry.isIntersecting) {
                    els.stickyCta.classList.remove('is-visible');
                } else {
                    els.stickyCta.classList.add('is-visible');
                }
            });
        }, { threshold: 0.24 });

        observer.observe(topSection);
    }

    let revealObserver;
    function observeRevealElements() {
        if (!revealObserver) {
            revealObserver = new IntersectionObserver((entries) => {
                entries.forEach((entry) => {
                    if (entry.isIntersecting) {
                        entry.target.classList.add('is-visible');
                        revealObserver.unobserve(entry.target);
                    }
                });
            }, {
                threshold: 0.14,
                rootMargin: '0px 0px -8% 0px'
            });
        }

        document.querySelectorAll('.reveal:not(.is-visible)').forEach((node) => revealObserver.observe(node));
    }

    function initParallax() {
        const nodes = Array.from(document.querySelectorAll('[data-parallax]'));
        if (!nodes.length) return;

        const update = () => {
            const y = window.scrollY;
            nodes.forEach((node) => {
                const speed = Number(node.dataset.parallax || 0.04);
                node.style.transform = `translate3d(0, ${Math.round(y * speed)}px, 0)`;
            });
        };

        update();
        window.addEventListener('scroll', update, { passive: true });
    }

    function initEvents() {
        if (els.extensionSearch) {
            els.extensionSearch.addEventListener('input', () => {
                state.query = els.extensionSearch.value;
                renderExtensions();
            });
        }

        els.retryExtensionStats?.addEventListener('click', fetchExtensionStats);
        els.retryDmg?.addEventListener('click', resolveDirectDmgUrl);

        els.openDownloadButtons.forEach((button) => {
            button.addEventListener('click', (event) => {
                event.preventDefault();
                openDownloadModal();
            });
        });

        els.closeDownloadModal?.addEventListener('click', closeDownloadModal);
        els.closeExtensionModal?.addEventListener('click', closeExtensionModal);

        els.downloadModal?.addEventListener('click', (event) => {
            if (event.target === els.downloadModal) closeDownloadModal();
        });
        els.extensionModal?.addEventListener('click', (event) => {
            if (event.target === els.extensionModal) closeExtensionModal();
        });

        document.addEventListener('keydown', (event) => {
            if (event.key !== 'Escape') return;
            if (els.extensionModal?.classList.contains('is-active')) closeExtensionModal();
            else if (els.downloadModal?.classList.contains('is-active')) closeDownloadModal();
        });
    }

    function init() {
        renderNativeLayer();
        renderCoreFeatures();
        renderExtensionChips();
        renderExtensions();
        initEvents();
        initNavTracking();
        initStickyCta();
        initParallax();
        observeRevealElements();

        fetchExtensionStats();
        resolveDirectDmgUrl();
    }

    document.addEventListener('DOMContentLoaded', init);
})();
