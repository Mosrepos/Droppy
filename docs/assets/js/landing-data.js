(() => {
    const SUPABASE_URL = 'https://anannmonpspjsnfgdglb.supabase.co';
    const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFuYW5ubW9ucHNwanNuZmdkZ2xiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc1NDgxODQsImV4cCI6MjA4MzEyNDE4NH0.5BvuW5cS0kJCuA2Nm5HCVDLNWNzn6EA_8JVVrW6pfnY';

    const extensionIdMap = {
        'ai-bg': 'aiBackgroundRemoval',
        'alfred': 'alfred',
        'apple-music': 'appleMusic',
        'element-capture': 'elementCapture',
        'finder': 'finder',
        'high-alert': 'caffeine',
        'spotify': 'spotify',
        'voice-transcribe': 'voiceTranscribe',
        'window-snap': 'windowSnap',
        'video-target-size': 'ffmpegVideoCompression',
        'termi-notch': 'terminalNotch',
        'camera': 'camera',
        'quickshare': 'quickshare',
        'notify-me': 'notificationHUD',
        'todo': 'todo',
        'menu-bar-manager': 'menuBarManager'
    };

    const extensionCategories = [
        { id: 'all', label: 'All' },
        { id: 'productivity', label: 'Productivity' },
        { id: 'ai', label: 'AI' },
        { id: 'media', label: 'Media' },
        { id: 'utilities', label: 'Utilities' },
        { id: 'community', label: 'Community' }
    ];

    const extensions = [
        {
            id: 'ai-bg',
            title: 'AI Background Removal',
            category: 'ai',
            categoryLabel: 'AI',
            icon: 'assets/icons/ai-bg.jpg',
            screenshot: 'assets/images/ai-bg-screenshot.png',
            deepUrl: 'droppy://extension/ai-bg',
            description: 'Remove backgrounds from images instantly using local AI processing. No internet connection required.',
            features: ['On-device AI processing', 'No internet required', 'Instant results', 'Multiple format support', 'Batch processing'],
            tags: ['AI', 'Image']
        },
        {
            id: 'alfred',
            title: 'Alfred Workflows',
            category: 'productivity',
            categoryLabel: 'Productivity',
            icon: 'assets/icons/alfred.png',
            screenshot: 'assets/images/alfred-screenshot.png',
            deepUrl: 'droppy://extension/alfred',
            description: 'Seamlessly add files to Droppy\'s Shelf or Basket directly from Alfred using keyboard shortcuts.',
            features: ['Trigger workflows from basket', 'Quick access to favorites', 'Keyboard shortcuts', 'Deep linking support'],
            tags: ['Automation', 'Workflow']
        },
        {
            id: 'apple-music',
            title: 'Apple Music',
            category: 'media',
            categoryLabel: 'Media',
            icon: 'assets/icons/apple-music.png',
            screenshot: 'assets/images/applemusic-screenshot.jpg',
            deepUrl: 'droppy://extension/apple-music',
            description: 'Control Apple Music playback from your notch. Shuffle, repeat, and love songs with native AppleScript integration.',
            features: ['Now Playing widget in notch', 'Shuffle and repeat controls', 'Love songs instantly', 'Album artwork display', 'Enabled by default'],
            tags: ['Music', 'Playback']
        },
        {
            id: 'element-capture',
            title: 'Element Capture',
            category: 'utilities',
            categoryLabel: 'Utilities',
            icon: 'assets/icons/element-capture.jpg',
            screenshot: 'assets/images/element-capture-screenshot.gif',
            deepUrl: 'droppy://extension/element-capture',
            description: 'Capture screen elements, annotate with arrows, shapes, text, and blur sensitive content, then copy or add to Droppy.',
            features: ['Element detection', 'Annotate with arrows and shapes', 'Add text labels', 'Blur sensitive content', 'Auto-cropping', 'Quick save to basket'],
            tags: ['Capture', 'Editing']
        },
        {
            id: 'finder',
            title: 'Finder Services',
            category: 'utilities',
            categoryLabel: 'Utilities',
            icon: 'assets/icons/finder.png',
            screenshot: 'assets/images/finder-screenshot.png',
            deepUrl: 'droppy://extension/finder',
            description: 'Access Droppy directly from Finder\'s right-click menu and add selected files to Shelf or Basket without switching apps.',
            features: ['Services menu integration', 'Right-click actions', 'Quick add to basket', 'Process with extensions'],
            tags: ['Finder', 'Files']
        },
        {
            id: 'high-alert',
            title: 'High Alert',
            category: 'community',
            categoryLabel: 'Productivity · Community',
            icon: 'assets/icons/high-alert.jpg',
            screenshot: 'assets/images/high-alert-screenshot.gif',
            deepUrl: 'droppy://extension/caffeine',
            description: 'Prevent your Mac from going to sleep with indefinite mode or timed sessions for long-running workflows.',
            features: ['Keep Mac awake indefinitely', 'Set sleep prevention timer', 'Hover notch to see remaining time', 'Lightweight, no battery drain', 'Quick toggle from notch'],
            tags: ['Community', 'Power']
        },
        {
            id: 'spotify',
            title: 'Spotify Integration',
            category: 'media',
            categoryLabel: 'Media',
            icon: 'assets/icons/spotify.png',
            screenshot: 'assets/images/spotify-screenshot.jpg',
            deepUrl: 'droppy://extension/spotify',
            description: 'Control Spotify playback directly from your notch with album art, track info, and playback controls.',
            features: ['Now Playing widget in notch', 'Playback controls', 'Volume adjustment', 'Album artwork display', 'Keyboard shortcuts'],
            tags: ['Music', 'Streaming']
        },
        {
            id: 'voice-transcribe',
            title: 'Voice Transcribe',
            category: 'ai',
            categoryLabel: 'AI',
            icon: 'assets/icons/voice-transcribe.jpg',
            screenshot: 'assets/images/voice-transcribe-screenshot.png',
            deepUrl: 'droppy://extension/voice-transcribe',
            description: 'Transcribe audio recordings to text using WhisperKit AI with fully local processing for complete privacy.',
            features: ['On-device Whisper AI', 'Multiple language support', 'Audio file upload', 'Real-time transcription', 'Export to text'],
            tags: ['AI', 'Audio']
        },
        {
            id: 'window-snap',
            title: 'Window Snap',
            category: 'productivity',
            categoryLabel: 'Productivity',
            icon: 'assets/icons/window-snap.jpg',
            screenshot: 'assets/images/window-snap-screenshot.png',
            deepUrl: 'droppy://extension/window-snap',
            description: 'Snap windows to halves, quarters, thirds, or full screen with customizable keyboard shortcuts and multi-monitor support.',
            features: ['Keyboard shortcuts', 'Custom snap areas', 'Multi-monitor support', 'Edge snapping', 'Remembers positions'],
            tags: ['Windows', 'Layout']
        },
        {
            id: 'video-target-size',
            title: 'Video Target Size',
            category: 'media',
            categoryLabel: 'Media',
            icon: 'assets/icons/targeted-video-size.jpg',
            screenshot: 'assets/images/video-target-size-screenshot.png',
            deepUrl: 'droppy://extension/video-target-size',
            description: 'Compress videos to exact file sizes using FFmpeg two-pass encoding for Discord, email, and social platforms.',
            features: ['Exact file size targeting', 'Two-pass encoding', 'H.264 and AAC output', 'One-time FFmpeg install', 'Fast processing'],
            tags: ['Video', 'Compression']
        },
        {
            id: 'termi-notch',
            title: 'Termi-Notch',
            category: 'productivity',
            categoryLabel: 'Productivity',
            icon: 'assets/icons/terminotch.jpg',
            screenshot: 'assets/images/terminal-notch-screenshot.png',
            deepUrl: 'droppy://extension/termi-notch',
            description: 'Run terminal commands instantly from your notch using quick and expanded command modes.',
            features: ['Full terminal emulation', 'Custom keyboard shortcut', 'Quick command mode', 'Expanded mode for output', 'Open in Terminal.app'],
            tags: ['Terminal', 'Power User']
        },
        {
            id: 'camera',
            title: 'Notchface',
            category: 'productivity',
            categoryLabel: 'Productivity',
            icon: 'assets/icons/snap-camera-v2.png',
            screenshot: 'assets/screenshots/notchface.png',
            deepUrl: 'droppy://extension/camera',
            description: 'Adds a floating camera toggle below the shelf and opens a polished full camera preview in the notch shelf.',
            features: ['Floating camera toggle button', 'Full preview mode in shelf', 'Smooth low-latency startup', 'Consistent spacing with other shelf views'],
            tags: ['Camera', 'Meetings']
        },
        {
            id: 'quickshare',
            title: 'Droppy Quickshare',
            category: 'utilities',
            categoryLabel: 'Utilities',
            icon: 'assets/icons/quickshare.jpg',
            screenshot: 'assets/images/quickshare-screenshot.png',
            deepUrl: 'droppy://extension/quickshare',
            description: 'Upload files to the cloud and generate shareable links instantly with automatic expiration.',
            features: ['Instant shareable links', 'Auto-expiring files', 'No account needed', 'Drag and drop upload', 'Built-in file manager'],
            tags: ['Sharing', 'Cloud']
        },
        {
            id: 'notify-me',
            title: 'Notify me!',
            category: 'community',
            categoryLabel: 'Productivity · Community',
            icon: 'assets/icons/notification-hud.png',
            screenshot: 'assets/images/notification-hud-screenshot.png',
            deepUrl: 'droppy://extension/notification-hud',
            description: 'Capture macOS notifications and display them in the notch with quick open and dismiss gestures.',
            features: ['Display notifications in the notch', 'Show app icon and preview text', 'Click to open, swipe to dismiss', 'Per-app notification filtering', 'Requires Full Disk Access'],
            tags: ['Community', 'Notifications']
        },
        {
            id: 'todo',
            title: 'Reminders',
            category: 'community',
            categoryLabel: 'Productivity · Community',
            icon: 'assets/icons/reminders.png',
            screenshot: 'assets/images/reminders-screenshot.gif',
            deepUrl: 'droppy://extension/todo',
            description: 'Capture tasks in natural language and sync with Apple Reminders, including priorities and date parsing.',
            features: ['Natural-language task capture', 'List support with list mentions', 'Date mentions like tomorrow and next Friday', 'Multilingual task input', 'Priority levels and auto-cleanup'],
            tags: ['Community', 'Tasks']
        },
        {
            id: 'menu-bar-manager',
            title: 'Menu Bar Manager',
            category: 'community',
            categoryLabel: 'Productivity · Community',
            icon: 'assets/icons/menubarmanager.png',
            screenshot: null,
            deepUrl: 'droppy://extension/menu-bar-manager',
            description: 'Clean up your menu bar with hidden-icon zones and the Floating Bar Manager directly below your menu bar.',
            features: ['Floating Bar Manager (major feature)', 'Eye icon visibility toggles', 'Chevron hidden zone indicator', 'Drag left of chevron to hide', 'Rearrange with Command+drag', 'Remembers your layout'],
            tags: ['Community', 'Menu Bar']
        }
    ];

    const nativeLayerClusters = [
        {
            title: 'Capture and Stage',
            description: 'Drag files, text, and media into one persistent notch layer.',
            items: ['File Shelf', 'Floating Basket', 'Drag-out anywhere', 'Quick Look previews']
        },
        {
            title: 'Recall Instantly',
            description: 'Bring back anything you copied with reliable, searchable history.',
            items: ['Clipboard history', 'Tags and favorites', 'Flagged entries', 'Fast search']
        },
        {
            title: 'Control the System',
            description: 'Turn stock overlays into native-feeling controls and HUDs.',
            items: ['Volume and brightness HUDs', 'Media controls', 'AirPods states', 'External display support']
        },
        {
            title: 'Extend Your Workflow',
            description: 'Plug in optional modules without bloating your core setup.',
            items: ['16+ extensions', 'Community modules', 'One-click deep links', 'All included in one license']
        }
    ];

    const coreFeatureBlocks = [
        {
            id: 'file-shelf',
            eyebrow: 'Core Feature',
            title: 'File Shelf',
            description: 'Drop files, folders, links, and snippets into the notch and keep them there until you need them.',
            image: 'assets/images/feature-shelf.png',
            bullets: [
                { title: 'Universal Drag and Drop', text: 'Move assets between apps without context switching.' },
                { title: 'Folders and Tracked Sources', text: 'Pin folders or mirror watched directories directly in the shelf.' },
                { title: 'Action-Rich Context Menu', text: 'Share, AirDrop, rename, compress, OCR, and more from one place.' }
            ]
        },
        {
            id: 'floating-basket',
            eyebrow: 'Core Feature',
            title: 'Floating Basket',
            description: 'Jiggle your pointer while dragging to spawn floating baskets wherever your workflow is happening.',
            image: 'assets/images/feature-basket.png',
            bullets: [
                { title: 'Spawn on Demand', text: 'Summon a temporary drop target exactly where you need it.' },
                { title: 'Color-Coded Baskets', text: 'Group files by task using multiple visual baskets.' },
                { title: 'Batch Handling', text: 'Drop, collect, and dispatch multiple files in one motion.' }
            ]
        },
        {
            id: 'clipboard-manager',
            eyebrow: 'Core Feature',
            title: 'Clipboard Manager',
            description: 'Store every copy action with searchable, persistent history and fast retrieval from anywhere.',
            image: 'assets/images/feature-clipboard.png',
            bullets: [
                { title: 'Persistent Capture', text: 'Text, media, files, links, and colors stay available across sessions.' },
                { title: 'Organize and Find', text: 'Use tags, favorites, and full-text search to find the exact item quickly.' },
                { title: 'Inline Quick Actions', text: 'Paste, copy, flag, rename, or delete with rich previews.' }
            ]
        },
        {
            id: 'native-huds',
            eyebrow: 'Core Feature',
            title: 'Native HUD Layer',
            description: 'Replace default overlays with a polished notch-first interface for media and hardware controls.',
            image: 'assets/images/feature-huds.png',
            bullets: [
                { title: 'Hardware Controls', text: 'Volume and brightness HUDs for built-in and external displays.' },
                { title: 'Media Experience', text: 'Album art, transport controls, scrubbing, and visualizer at the notch.' },
                { title: 'Device Awareness', text: 'AirPods, battery state, and keyboard indicators with clear feedback.' }
            ]
        }
    ];

    window.DROPPY_LANDING_DATA = {
        SUPABASE_URL,
        SUPABASE_ANON_KEY,
        extensionIdMap,
        extensionCategories,
        extensions,
        nativeLayerClusters,
        coreFeatureBlocks
    };
})();
