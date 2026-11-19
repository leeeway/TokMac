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

    function getActiveVideo() {
        const { innerWidth: width, innerHeight: height } = window;
        let best = null;
        for (const video of document.querySelectorAll('video')) {
            const rect = video.getBoundingClientRect();
            const visibleWidth = Math.min(rect.right, width) - Math.max(rect.left, 0);
            const visibleHeight = Math.min(rect.bottom, height) - Math.max(rect.top, 0);
            if (visibleWidth <= 0 || visibleHeight <= 0) continue;
            const area = visibleWidth * visibleHeight;
            if (area < 0.1 * Math.min(rect.width * rect.height, width * height)) continue;
            const style = window.getComputedStyle?.(video);
            if (style?.visibility === 'hidden' || style?.visibility === 'collapse' || style?.opacity === '0') continue;

            const playing = video.paused === false && !video.ended;
            const distance = Math.hypot((rect.left + rect.right - width) / 2, (rect.top + rect.bottom - height) / 2);
            if (!best || (playing && !best.playing) ||
                (playing === best.playing && (area > best.area || (area === best.area && distance < best.distance)))) {
                best = { video, playing, area, distance };
            }
        }
        return best?.video ?? null;
    }

    function videoCard(video) {
        return video.closest('[data-e2e="recommend-list-item-container"], article, [data-e2e="feed-item"]');
    }

    function videoPermalink(value) {
        if (!value) return null;
        try {
            const url = new URL(value, window.location.href);
            if (url.protocol !== 'https:' || url.port || url.username || url.password ||
                (url.hostname !== 'tiktok.com' && !url.hostname.endsWith('.tiktok.com'))) return null;
            const path = url.pathname.match(/^\/@([A-Za-z0-9._]{1,64})\/video\/([0-9]{1,32})\/?$/);
            return path ? `https://www.tiktok.com/@${path[1]}/video/${path[2]}` : null;
        } catch (_) { return null; }
    }

    window.tokmacCurrentVideoLink = function() {
        const video = getActiveVideo();
        if (!video) return null;
        const directLink = videoPermalink(video.closest('a[href]')?.href);
        if (directLink) return directLink;

        const card = videoCard(video);
        const links = new Set(Array.from(card?.querySelectorAll('a[href]') ?? [], link => videoPermalink(link.href))
            .filter(Boolean));
        if (links.size === 1) return links.values().next().value;
        const detailLink = videoPermalink(window.location.href);
        if (detailLink && (links.has(detailLink) ||
            (links.size === 0 && (video.closest('[role="dialog"], [data-e2e="browse-video"]') ||
                document.querySelectorAll('video').length === 1)))) return detailLink;
        return null;
    };

    function navigateVideo(direction) {
        const video = getActiveVideo();
        if (!video) return;
        const forward = direction > 0;
        const feedControl = forward ? '[data-e2e="feed-arrow-down"]' : '[data-e2e="feed-arrow-up"]';
        const videoLabel = forward
            ? 'button[aria-label="Next video" i], button[aria-label="下一个视频"]'
            : 'button[aria-label="Previous video" i], button[aria-label="上一个视频"]';
        const dialog = video.closest('[role="dialog"]');
        const feed = video.closest('[data-e2e="recommend-list"], [data-e2e="feed-list"], main');
        const scope = dialog || feed || document;
        const button = scope.querySelector(feedControl) || scope.querySelector(videoLabel);
        if (button && !button.disabled) {
            button.click();
            return;
        }
        // Scroll the container owning this player instead of the page or an unrelated carousel.
        for (let parent = video.parentElement; parent && parent !== document.body; parent = parent.parentElement) {
            if (parent.scrollHeight > parent.clientHeight &&
                /^(auto|scroll|overlay)$/.test(window.getComputedStyle?.(parent)?.overflowY ?? '')) {
                parent.scrollBy({ top: direction * parent.clientHeight * 0.85, behavior: 'smooth' });
                return;
            }
            if (parent === dialog) return;
        }
        if (!dialog) window.scrollBy({ top: direction * window.innerHeight * 0.85, behavior: 'smooth' });
    }

    window.tokmacNextVideo = () => navigateVideo(1);
    window.tokmacPrevVideo = () => navigateVideo(-1);

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
        const video = getActiveVideo();
        if (!video) return;
        const selector = 'button[data-e2e="feed-comment-icon"], span[data-e2e="comment-icon"], ' +
            '[data-e2e="feed-comment-button"], button[aria-label*="Comment"], button[aria-label*="评论"]';
        const card = videoCard(video);
        const commentBtn = card?.querySelector(selector);
        if (commentBtn) {
            commentBtn.click();
        } else if (document.querySelectorAll('video').length === 1) {
            // A dedicated video page may put its comment control beside the player.
            const buttons = document.querySelectorAll(selector);
            if (buttons.length === 1) buttons[0].click();
        }
    };

    function isEditing(element) {
        return !!element && (element.isContentEditable ||
            !!element.closest?.('input, textarea, select, [role="textbox"], [role="combobox"], button, a[href], [role="button"]'));
    }

    window.addEventListener('keydown', function(event) {
        if (event.defaultPrevented || event.isComposing || event.keyCode === 229 ||
            event.metaKey || event.ctrlKey || event.altKey || event.shiftKey ||
            document.designMode === 'on' || isEditing(event.target) || isEditing(document.activeElement)) return;
        const action = {
            j: window.tokmacNextVideo, ArrowDown: window.tokmacNextVideo,
            k: window.tokmacPrevVideo, ArrowUp: window.tokmacPrevVideo,
            ' ': window.tokmacTogglePlay, m: window.tokmacToggleMute, c: window.tokmacToggleComments
        }[event.key];
        if (!action || !getActiveVideo()) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        if (!event.repeat) action();
    }, true);

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
        const card = videoCard(video);
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
