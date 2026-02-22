(function () {
    const API_URL = 'https://api.github.com/repos/iordv/Droppy/releases/latest';
    const CACHE_KEY = 'droppy_latest_release_notes';
    const CACHE_DURATION_MS = 1000 * 60 * 30;

    function getCachedRelease() {
        const raw = localStorage.getItem(CACHE_KEY);
        if (!raw) return null;

        try {
            const parsed = JSON.parse(raw);
            if (!parsed || !parsed.timestamp || !parsed.data) return null;
            if (Date.now() - parsed.timestamp > CACHE_DURATION_MS) return null;
            return parsed.data;
        } catch (error) {
            localStorage.removeItem(CACHE_KEY);
            return null;
        }
    }

    function setCachedRelease(data) {
        localStorage.setItem(CACHE_KEY, JSON.stringify({
            timestamp: Date.now(),
            data
        }));
    }

    function parseBulletSection(markdownBody, sectionMatchers) {
        const lines = markdownBody.split(/\r?\n/);
        let startIndex = -1;

        for (let index = 0; index < lines.length; index += 1) {
            const trimmed = lines[index].trim();
            if (sectionMatchers.some((matcher) => matcher.test(trimmed))) {
                startIndex = index + 1;
                break;
            }
        }

        if (startIndex === -1) return [];

        const bullets = [];
        for (let index = startIndex; index < lines.length; index += 1) {
            const trimmed = lines[index].trim();

            if (/^\*\*.+\*\*$/.test(trimmed) || /^##\s+/.test(trimmed)) {
                break;
            }

            if (/^- /.test(trimmed)) {
                bullets.push(trimmed.replace(/^- /, '').replace(/`/g, ''));
            }
        }

        return bullets;
    }

    function renderList(container, items, fallbackText) {
        if (!container) return;
        container.innerHTML = '';

        const content = items.length > 0 ? items : [fallbackText];
        content.slice(0, 15).forEach((item) => {
            const li = document.createElement('li');
            li.textContent = item;
            container.appendChild(li);
        });
    }

    function setStatus(statusRow, retryButton, state, message, canRetry) {
        if (!statusRow) return;
        statusRow.dataset.state = state;

        const textEl = statusRow.querySelector('[data-status-text]');
        if (textEl) textEl.textContent = message;

        if (retryButton) {
            retryButton.style.display = canRetry ? 'inline-flex' : 'none';
        }
    }

    function renderRelease(release, nodes) {
        const body = release.body || '';
        const tag = release.tag_name || release.name || 'latest';

        nodes.titleEl.textContent = `What's New in ${tag}`;
        nodes.descEl.textContent = 'Auto-synced from latest GitHub release notes.';
        nodes.linkEl.href = release.html_url || 'https://github.com/iordv/Droppy/releases/latest';

        const newFeatures = parseBulletSection(body, [
            /^\*\*new features\*\*$/i,
            /^##\s+new features$/i
        ]);
        const bugFixes = parseBulletSection(body, [
            /^\*\*bug fixes.*\*\*$/i,
            /^##\s+bug fixes/i
        ]);

        renderList(nodes.newListEl, newFeatures, 'See full release notes on GitHub.');
        renderList(nodes.fixListEl, bugFixes, 'See full release notes on GitHub.');
    }

    async function fetchLatestRelease() {
        const response = await fetch(API_URL);
        if (!response.ok) {
            throw new Error(`Failed to fetch latest release: ${response.status}`);
        }

        const data = await response.json();
        setCachedRelease(data);
        return data;
    }

    async function loadRelease(nodes, options) {
        const useCache = options && options.useCache;

        if (useCache) {
            const cached = getCachedRelease();
            if (cached) {
                renderRelease(cached, nodes);
                setStatus(nodes.statusRow, nodes.retryButton, 'success', 'Loaded from recent cache.', false);
                return;
            }
        }

        setStatus(nodes.statusRow, nodes.retryButton, 'loading', 'Syncing release notes from GitHub...', false);

        const release = await fetchLatestRelease();
        renderRelease(release, nodes);
        setStatus(nodes.statusRow, nodes.retryButton, 'success', 'Release notes are up to date.', false);
    }

    async function init() {
        const nodes = {
            titleEl: document.getElementById('latest-release-title'),
            descEl: document.getElementById('latest-release-description'),
            linkEl: document.getElementById('latest-release-link'),
            newListEl: document.getElementById('latest-release-new'),
            fixListEl: document.getElementById('latest-release-fixes'),
            statusRow: document.getElementById('latest-release-status'),
            retryButton: document.getElementById('latest-release-retry')
        };

        if (!nodes.titleEl || !nodes.descEl || !nodes.linkEl || !nodes.newListEl || !nodes.fixListEl) {
            return;
        }

        try {
            await loadRelease(nodes, { useCache: true });
        } catch (error) {
            console.error('Release notes failed to load:', error);
            nodes.titleEl.textContent = 'What\'s New';
            nodes.descEl.textContent = 'Could not load release notes right now.';
            nodes.linkEl.href = 'https://github.com/iordv/Droppy/releases/latest';
            renderList(nodes.newListEl, [], 'Open latest release notes on GitHub.');
            renderList(nodes.fixListEl, [], 'Open latest release notes on GitHub.');
            setStatus(nodes.statusRow, nodes.retryButton, 'error', 'GitHub release sync failed. Retry to fetch latest notes.', true);
        }

        if (nodes.retryButton) {
            nodes.retryButton.addEventListener('click', async () => {
                try {
                    await loadRelease(nodes, { useCache: false });
                } catch (error) {
                    console.error('Retrying release notes failed:', error);
                    setStatus(nodes.statusRow, nodes.retryButton, 'error', 'Retry failed. Check connection and try again.', true);
                }
            });
        }
    }

    document.addEventListener('DOMContentLoaded', init);
})();
