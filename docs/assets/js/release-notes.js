(function () {
    const API_URL = 'https://api.github.com/repos/iordv/Droppy/releases/latest';
    const CACHE_KEY = 'droppy_latest_release_notes';
    const CACHE_DURATION_MS = 1000 * 60 * 30;

    function getCachedRelease() {
        const raw = localStorage.getItem(CACHE_KEY);
        if (!raw) return null;
        try {
            const parsed = JSON.parse(raw);
            if (Date.now() - parsed.timestamp > CACHE_DURATION_MS) return null;
            return parsed.data;
        } catch (e) {
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

        for (let i = 0; i < lines.length; i += 1) {
            const trimmed = lines[i].trim();
            if (sectionMatchers.some((matcher) => matcher.test(trimmed))) {
                startIndex = i + 1;
                break;
            }
        }

        if (startIndex === -1) return [];

        const bullets = [];
        for (let i = startIndex; i < lines.length; i += 1) {
            const trimmed = lines[i].trim();

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
        container.innerHTML = '';
        const listItems = items.length > 0 ? items : [fallbackText];
        for (const item of listItems.slice(0, 15)) {
            const li = document.createElement('li');
            li.textContent = item;
            container.appendChild(li);
        }
    }

    async function fetchLatestRelease() {
        const cached = getCachedRelease();
        if (cached) return cached;

        const response = await fetch(API_URL);
        if (!response.ok) {
            throw new Error(`Failed to fetch latest release: ${response.status}`);
        }
        const data = await response.json();
        setCachedRelease(data);
        return data;
    }

    async function init() {
        const titleEl = document.getElementById('latest-release-title');
        const descEl = document.getElementById('latest-release-description');
        const linkEl = document.getElementById('latest-release-link');
        const newListEl = document.getElementById('latest-release-new');
        const fixListEl = document.getElementById('latest-release-fixes');

        if (!titleEl || !descEl || !linkEl || !newListEl || !fixListEl) return;

        try {
            const release = await fetchLatestRelease();
            const body = release.body || '';
            const tag = release.tag_name || release.name || 'latest';

            titleEl.textContent = `What's New in ${tag}`;
            descEl.textContent = 'Auto-synced from latest GitHub release notes.';
            linkEl.href = release.html_url || 'https://github.com/iordv/Droppy/releases/latest';

            const newFeatures = parseBulletSection(body, [
                /^\*\*new features\*\*$/i,
                /^##\s+new features$/i
            ]);
            const bugFixes = parseBulletSection(body, [
                /^\*\*bug fixes.*\*\*$/i,
                /^##\s+bug fixes/i
            ]);

            renderList(newListEl, newFeatures, 'See full release notes on GitHub.');
            renderList(fixListEl, bugFixes, 'See full release notes on GitHub.');
        } catch (error) {
            titleEl.textContent = "What's New";
            descEl.textContent = 'Could not load release notes right now.';
            linkEl.href = 'https://github.com/iordv/Droppy/releases/latest';
            renderList(newListEl, [], 'Open latest release notes on GitHub.');
            renderList(fixListEl, [], 'Open latest release notes on GitHub.');
        }
    }

    document.addEventListener('DOMContentLoaded', init);
})();
