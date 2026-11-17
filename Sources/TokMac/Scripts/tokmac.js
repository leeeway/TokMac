(function() {
    if (window.__tokmac_injected) return;
    window.__tokmac_injected = true;

    if (window !== window.top || !isTrustedPage()) return;

    function isTrustedPage() {
        const host = window.location.hostname;
        return window.location.protocol === 'https:' &&
            (host === 'tiktok.com' || host.endsWith('.tiktok.com'));
    }

    function installStyle() {
        if (document.getElementById('__tokmac_clean_style')) return;
        const parent = document.head || document.documentElement;
        if (!parent) return;
        const style = document.createElement('style');
        style.id = '__tokmac_clean_style';
        style.textContent = `/* TokMac Clean & Lightweight CSS */

/* Hide distracting download banners and app promotion prompts */
div[class*="DivBannerContainer"],
div[class*="DivDownloadLinkContainer"],
div[class*="DivMobileAppWrapper"],
div[class*="DivGetAppContainer"],
div[class*="DivDesktopDownloadPrompt"],
div[id*="get-app"],
div[class*="DivAppBannerContainer"],
div[class*="DivTopNavDownloadLink"] {
    display: none !important;
}

/* Sleek macOS scrollbar styling */
::-webkit-scrollbar {
    width: 6px;
    height: 6px;
}
::-webkit-scrollbar-track {
    background: transparent;
}
::-webkit-scrollbar-thumb {
    background: rgba(255, 255, 255, 0.2);
    border-radius: 4px;
}
::-webkit-scrollbar-thumb:hover {
    background: rgba(255, 255, 255, 0.4);
}`;
        parent.appendChild(style);
    }
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', installStyle, { once: true });
    } else {
        installStyle();
    }

    // Allow native right click on all elements including video
    window.addEventListener('contextmenu', function(e) {
        e.stopImmediatePropagation();
    }, true);

    // Active video finder
    function getActiveVideo() {
        const videos = Array.from(document.querySelectorAll('video'));
        if (!videos.length) return null;
        const centerY = window.innerHeight / 2;
        let bestVideo = null;
        let minDistance = 999999;
        for (const v of videos) {
            const rect = v.getBoundingClientRect();
            if (rect.width <= 0 || rect.height <= 0 || rect.bottom <= 0 ||
                rect.top >= window.innerHeight || rect.right <= 0 || rect.left >= window.innerWidth) continue;
            const dist = Math.abs((rect.top + rect.bottom) / 2 - centerY);
            if (dist < minDistance) {
                minDistance = dist;
                bestVideo = v;
            }
        }
        return bestVideo;
    }

    // Programmatic Navigation Helpers (called via menu or toolbar)
    window.tokmacNextVideo = function() {
        const downArrow = document.querySelector('button[aria-label*="Next"]') || 
                          document.querySelector('button[aria-label*="下一个"]') ||
                          document.querySelector('button[data-e2e="arrow-right"]') ||
                          document.querySelector('button[data-e2e="feed-arrow-down"]');
        if (downArrow) {
            downArrow.click();
        } else {
            window.scrollBy({ top: window.innerHeight * 0.85, behavior: 'smooth' });
        }
    };

    window.tokmacPrevVideo = function() {
        const upArrow = document.querySelector('button[aria-label*="Previous"]') || 
                        document.querySelector('button[aria-label*="上一个"]') ||
                        document.querySelector('button[data-e2e="arrow-left"]') ||
                        document.querySelector('button[data-e2e="feed-arrow-up"]');
        if (upArrow) {
            upArrow.click();
        } else {
            window.scrollBy({ top: -window.innerHeight * 0.85, behavior: 'smooth' });
        }
    };

    window.tokmacTogglePlay = function() {
        const v = getActiveVideo();
        if (!v) return;
        if (v.paused) v.play();
        else v.pause();
    };

    window.tokmacToggleMute = function() {
        const v = getActiveVideo();
        if (!v) return;
        v.muted = !v.muted;
    };

    window.tokmacToggleComments = function() {
        const commentBtn = document.querySelector('button[data-e2e="feed-comment-icon"]') ||
                           document.querySelector('span[data-e2e="comment-icon"]') ||
                           document.querySelector('[data-e2e="feed-comment-button"]') ||
                           document.querySelector('button[aria-label*="Comment"]') ||
                           document.querySelector('button[aria-label*="评论"]');
        if (commentBtn) commentBtn.click();
    };

    function httpURL(value) {
        if (typeof value !== 'string') return null;
        try {
            const url = new URL(value);
            return url.protocol === 'https:' || url.protocol === 'http:' ? url.href : null;
        } catch (_) { return null; }
    }

    function videoID(value) {
        return typeof value === 'string' ? value.match(/\/video\/(\d+)/)?.[1] : null;
    }

    // Only use metadata belonging to the visible card (or to a dedicated video page).
    // Never take the first unrelated recommendation from the hydration payload.
    function matchingMetadata(id) {
        if (!id) return null;
        const seen = new WeakSet();
        const stack = [window.__UNIVERSAL_DATA_FOR_REHYDRATION__];
        const payload = document.getElementById('__UNIVERSAL_DATA_FOR_REHYDRATION__');
        if (payload) {
            try { stack.push(JSON.parse(payload.textContent)); } catch (_) {}
        }
        let visited = 0;
        while (stack.length && visited++ < 20000) {
            const node = stack.pop();
            if (!node || typeof node !== 'object' || seen.has(node)) continue;
            seen.add(node);
            if (String(node.id ?? node.aweme_id ?? '') === id && node.video) return node;
            for (const child of Object.values(node)) {
                if (child && typeof child === 'object') stack.push(child);
            }
        }
        return null;
    }

    window.tokmacGetVideoDownloadInfo = function() {
        const video = getActiveVideo();
        if (!video) return null;
        const card = video.closest('[data-e2e="recommend-list-item-container"], article, [data-e2e="feed-item"]');
        const link = card?.querySelector('a[href*="/video/"]');
        const id = videoID(link?.href) || videoID(window.location.pathname);
        const metadata = matchingMetadata(id);
        const src = video.currentSrc || video.src;
        let url = httpURL(src);
        if (!url) {
            for (const source of video.querySelectorAll('source')) {
                url = httpURL(source.src);
                if (url) break;
            }
        }
        if (!url && metadata) {
            url = httpURL(metadata.video.downloadAddr) || httpURL(metadata.video.playAddr);
        }
        if (!url && typeof src === 'string' && src.startsWith('blob:')) {
            try {
                if (new URL(src).origin === window.location.origin) url = src;
            } catch (_) {}
        }
        if (!url) return null;
        const authorEl = card?.querySelector('[data-e2e="video-author-uniqueid"], [data-e2e="user-title"]');
        return {
            url,
            author: metadata?.author?.uniqueId || authorEl?.textContent?.trim() || 'TikTok',
            isBlob: url.startsWith('blob:')
        };
    };

    // The browser streams Blob bytes directly to its native download implementation.
    // No file paths, file contents, or native write privileges are exposed to JavaScript.
    window.tokmacDownloadBlob = function(url) {
        if (typeof url !== 'string' || !url.startsWith('blob:') ||
            new URL(url).origin !== window.location.origin) throw new Error('Invalid Blob origin');
        const anchor = document.createElement('a');
        anchor.href = url;
        anchor.download = 'TikTok_video.mp4';
        document.body.appendChild(anchor);
        anchor.click();
        anchor.remove();
    };
})();
