import Foundation

enum InjectedScripts {
    static let cleanModeCSS = """
    /* TokMac Clean Mode CSS */

    /* Hide top nav banner, desktop download promos, and mobile app download bars */
    div[class*="DivBannerContainer"],
    div[class*="DivDownloadLinkContainer"],
    div[class*="DivMobileAppWrapper"],
    div[class*="DivGetAppContainer"],
    div[class*="DivDesktopDownloadPrompt"],
    a[href*="download"],
    div[id*="get-app"],
    div[class*="DivAppBannerContainer"],
    div[class*="DivTopNavDownloadLink"] {
        display: none !important;
    }

    /* In compact/phone view: completely eliminate left sidebar offset */
    body.tokmac-compact header,
    body.tokmac-compact aside,
    body.tokmac-compact [class*="DivSideNavContainer"],
    body.tokmac-compact [class*="DivSideNavWrapper"],
    body.tokmac-compact [class*="DivSidebarContainer"] {
        display: none !important;
        width: 0 !important;
        min-width: 0 !important;
        max-width: 0 !important;
        margin: 0 !important;
        padding: 0 !important;
    }

    /* Reset all leftover margins and paddings on body & main wrappers */
    body.tokmac-compact,
    body.tokmac-compact [class*="DivBodyContainer"],
    body.tokmac-compact [class*="DivMainContainer"],
    body.tokmac-compact [class*="DivContentContainer"],
    body.tokmac-compact [class*="DivThreeColumnContainer"],
    body.tokmac-compact [class*="DivFeedContainer"] {
        margin-left: 0 !important;
        padding-left: 0 !important;
        margin-right: 0 !important;
        padding-right: 0 !important;
        width: 100% !important;
        max-width: 100% !important;
    }

    /* Center video item and ensure right action bar is fully visible */
    body.tokmac-compact [class*="DivItemContainer"],
    body.tokmac-compact [class*="DivItemContainerV2"],
    body.tokmac-compact [class*="DivVideoItemContainer"] {
        display: flex !important;
        justify-content: center !important;
        align-items: flex-end !important;
        margin: 0 auto !important;
        padding: 0 4px !important;
        box-sizing: border-box !important;
    }

    /* Make sure action buttons (Like, Comment, Share, Download) stay visible */
    [class*="DivActionItemContainer"],
    [class*="DivActionContainer"],
    [data-e2e="feed-action-item"] {
        z-index: 100 !important;
        margin-left: 8px !important;
    }

    /* Smooth sleek scrollbars */
    ::-webkit-scrollbar {
        width: 5px;
        height: 5px;
    }
    ::-webkit-scrollbar-track {
        background: transparent;
    }
    ::-webkit-scrollbar-thumb {
        background: rgba(255, 255, 255, 0.25);
        border-radius: 4px;
    }
    ::-webkit-scrollbar-thumb:hover {
        background: rgba(255, 255, 255, 0.5);
    }
    """

    static let keyboardAndNavigationJS = """
    (function() {
        if (window.__tokmac_injected) return;
        window.__tokmac_injected = true;

        console.log("[TokMac] Injected script initialized.");

        let autoPlayNext = false;
        let lastCommentState = false;

        function findNextButton() {
            return document.querySelector('button[data-e2e="arrow-down"]') ||
                   document.querySelector('button[aria-label*="Next"]') ||
                   document.querySelector('button[aria-label*="down" i]') ||
                   document.querySelector('button[aria-label*="下" i]');
        }

        function findPrevButton() {
            return document.querySelector('button[data-e2e="arrow-up"]') ||
                   document.querySelector('button[aria-label*="Previous"]') ||
                   document.querySelector('button[aria-label*="up" i]') ||
                   document.querySelector('button[aria-label*="上" i]');
        }

        function getActiveVideo() {
            const videos = Array.from(document.querySelectorAll('video'));
            if (!videos.length) return null;
            const centerY = window.innerHeight / 2;
            let bestVideo = videos[0];
            let minDistance = 999999;
            for (const v of videos) {
                const rect = v.getBoundingClientRect();
                const dist = Math.abs((rect.top + rect.bottom) / 2 - centerY);
                if (dist < minDistance) {
                    minDistance = dist;
                    bestVideo = v;
                }
            }
            return bestVideo;
        }

        window.tokmacNextVideo = function() {
            const nextBtn = findNextButton();
            if (nextBtn) {
                nextBtn.click();
            } else {
                window.scrollBy({ top: window.innerHeight * 0.9, behavior: 'smooth' });
            }
        };

        window.tokmacPrevVideo = function() {
            const prevBtn = findPrevButton();
            if (prevBtn) {
                prevBtn.click();
            } else {
                window.scrollBy({ top: -window.innerHeight * 0.9, behavior: 'smooth' });
            }
        };

        window.tokmacTogglePlay = function() {
            const v = getActiveVideo();
            if (v) {
                if (v.paused) {
                    v.play();
                } else {
                    v.pause();
                }
            }
        };

        window.tokmacToggleMute = function() {
            const v = getActiveVideo();
            if (v) {
                v.muted = !v.muted;
                const muteBtn = document.querySelector('button[data-e2e="volume-control"]');
                if (muteBtn) muteBtn.click();
            }
        };

        window.tokmacToggleLike = function() {
            const likeBtn = document.querySelector('span[data-e2e="like-icon"]') ||
                            document.querySelector('button[data-e2e="like-icon"]');
            if (likeBtn) likeBtn.click();
        };

        window.tokmacToggleComments = function() {
            const commentBtn = document.querySelector('button[data-e2e="comment-icon"]') ||
                               document.querySelector('span[data-e2e="comment-icon"]') ||
                               document.querySelector('[data-e2e="feed-comment-icon"]');
            if (commentBtn) {
                commentBtn.click();
            }
        };

        window.tokmacSetAutoNext = function(enabled) {
            autoPlayNext = enabled;
        };

        // Extract active video info for direct download
        window.tokmacGetVideoDownloadInfo = function() {
            const v = getActiveVideo();
            if (!v) return null;
            let src = v.currentSrc || v.src;
            if (!src) {
                const source = v.querySelector('source');
                if (source) src = source.src;
            }
            
            // Try to find author name and description
            const authorEl = document.querySelector('h3[data-e2e="browse-user-title"]') ||
                             document.querySelector('span[data-e2e="browse-user-title"]') ||
                             document.querySelector('span[data-e2e="user-title"]') ||
                             document.querySelector('a[data-e2e="video-author-uniqueid"]');
            const author = authorEl ? authorEl.innerText.trim() : 'TikTok';

            const descEl = document.querySelector('div[data-e2e="video-desc"]') ||
                           document.querySelector('h1[data-e2e="browse-video-desc"]');
            const desc = descEl ? descEl.innerText.trim().slice(0, 30) : '';

            return {
                url: src,
                author: author,
                description: desc
            };
        };

        // Monitor comment panel open/close state
        function checkCommentPanel() {
            const commentPanel = document.querySelector('[class*="DivCommentContainer"]') ||
                                 document.querySelector('[data-e2e="comment-list"]') ||
                                 document.querySelector('[class*="DivCommentListContainer"]');
            let isOpen = false;
            if (commentPanel) {
                const rect = commentPanel.getBoundingClientRect();
                isOpen = rect.width > 50 && rect.height > 50 && window.getComputedStyle(commentPanel).display !== 'none';
            }
            if (isOpen !== lastCommentState) {
                lastCommentState = isOpen;
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tokmac) {
                    window.webkit.messageHandlers.tokmac.postMessage({
                        type: 'commentPanelStateChanged',
                        isOpen: isOpen
                    });
                }
            }
        }
        setInterval(checkCommentPanel, 600);

        // Attach video ended listener for Auto Next
        function hookVideos() {
            const videos = document.querySelectorAll('video');
            videos.forEach(v => {
                if (!v.__tokmac_hooked) {
                    v.__tokmac_hooked = true;
                    v.addEventListener('ended', () => {
                        if (autoPlayNext) {
                            setTimeout(() => {
                                window.tokmacNextVideo();
                            }, 500);
                        }
                    });
                }
            });
        }
        setInterval(hookVideos, 1500);

        // Global Keyboard Shortcut listener
        window.addEventListener('keydown', function(e) {
            const target = e.target;
            if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable)) {
                return;
            }

            if (e.key === 'ArrowDown' || e.key === 'j' || e.key === 'J' || e.key === 's' || e.key === 'S') {
                e.preventDefault();
                window.tokmacNextVideo();
            } else if (e.key === 'ArrowUp' || e.key === 'k' || e.key === 'K' || e.key === 'w' || e.key === 'W') {
                e.preventDefault();
                window.tokmacPrevVideo();
            } else if (e.key === ' ' || e.code === 'Space') {
                e.preventDefault();
                window.tokmacTogglePlay();
            } else if (e.key === 'm' || e.key === 'M') {
                e.preventDefault();
                window.tokmacToggleMute();
            } else if (e.key === 'l' || e.key === 'L') {
                e.preventDefault();
                window.tokmacToggleLike();
            } else if (e.key === 'c' || e.key === 'C') {
                e.preventDefault();
                window.tokmacToggleComments();
            }
        }, true);
    })();
    """
}
