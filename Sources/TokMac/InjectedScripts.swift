import Foundation

enum InjectedScripts {
    static let cleanModeCSS = """
    /* TokMac Clean & Hover-Sidebar Mode */

    /* Hide top nav banner, desktop download promos, and mobile app download banners */
    div[class*="DivBannerContainer"],
    div[class*="DivDownloadLinkContainer"],
    div[class*="DivMobileAppWrapper"],
    div[class*="DivGetAppContainer"],
    div[class*="DivDesktopDownloadPrompt"],
    a[href*="download"],
    div[id*="get-app"],
    div[class*="DivAppBannerContainer"],
    div[class*="DivTopNavDownloadLink"],
    div[class*="DivTopNavContainer"] {
        display: none !important;
    }

    /* Left Sidebar: Hover Drawer Behavior */
    /* By default in compact mode, tuck sidebar off-screen to the left with smooth transition */
    body.tokmac-compact aside,
    body.tokmac-compact [class*="DivSideNavContainer"],
    body.tokmac-compact [class*="DivSideNavWrapper"],
    body.tokmac-compact [class*="DivSidebarContainer"] {
        position: fixed !important;
        top: 0 !important;
        bottom: 0 !important;
        left: -270px !important;
        width: 260px !important;
        max-width: 260px !important;
        z-index: 999999 !important;
        background: rgba(18, 18, 24, 0.95) !important;
        backdrop-filter: blur(25px) !important;
        -webkit-backdrop-filter: blur(25px) !important;
        border-right: 1px solid rgba(255, 255, 255, 0.12) !important;
        box-shadow: 10px 0 35px rgba(0, 0, 0, 0.6) !important;
        transition: left 0.28s cubic-bezier(0.16, 1, 0.3, 1) !important;
        display: block !important;
    }

    /* Reveal sidebar when mouse hovers or class active */
    body.tokmac-compact aside:hover,
    body.tokmac-compact [class*="DivSideNavContainer"]:hover,
    body.tokmac-compact [class*="DivSideNavWrapper"]:hover,
    body.tokmac-compact.tokmac-sidebar-open aside,
    body.tokmac-compact.tokmac-sidebar-open [class*="DivSideNavContainer"],
    body.tokmac-compact.tokmac-sidebar-open [class*="DivSideNavWrapper"] {
        left: 0 !important;
    }

    /* Reset all leftover margins and paddings on body & main wrappers to eliminate black bar */
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

    /* Video feed item layout: keep video and right-side action buttons aligned */
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

    /* Action buttons (Like, Comment, Favorite, Share) must be fully visible */
    [class*="DivActionItemContainer"],
    [class*="DivActionContainer"],
    [data-e2e="feed-action-item"] {
        z-index: 100 !important;
        margin-left: 10px !important;
        opacity: 1 !important;
        visibility: visible !important;
    }

    /* Ensure Comment Panel is visible and styled properly */
    [class*="DivCommentContainer"],
    [data-e2e="comment-list"],
    [class*="DivCommentListContainer"],
    [class*="DivModalContainer"] {
        visibility: visible !important;
        opacity: 1 !important;
        z-index: 1000 !important;
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

        console.log("[TokMac] Injected script v2 initialized.");

        let autoPlayNext = false;
        let lastCommentState = false;

        // 1. Force enable native Right-Click Context Menu (stop TikTok from suppressing it)
        window.addEventListener('contextmenu', function(e) {
            e.stopImmediatePropagation();
        }, true);

        // 2. Setup left edge hover zone to reveal sidebar
        function setupSidebarHover() {
            if (document.getElementById('__tokmac_sidebar_hover')) return;
            const hoverZone = document.createElement('div');
            hoverZone.id = '__tokmac_sidebar_hover';
            hoverZone.style.cssText = 'position:fixed;top:0;bottom:0;left:0;width:35px;z-index:999998;background:transparent;cursor:pointer;';
            hoverZone.addEventListener('mouseenter', () => {
                document.body.classList.add('tokmac-sidebar-open');
            });
            document.body.appendChild(hoverZone);

            document.addEventListener('mousemove', (e) => {
                if (e.clientX > 280) {
                    document.body.classList.remove('tokmac-sidebar-open');
                }
            });
        }
        if (document.body) {
            setupSidebarHover();
        } else {
            document.addEventListener('DOMContentLoaded', setupSidebarHover);
        }

        // 3. Navigation buttons helpers
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
                            document.querySelector('button[data-e2e="like-icon"]') ||
                            document.querySelector('[data-e2e="feed-like-icon"]');
            if (likeBtn) likeBtn.click();
        };

        window.tokmacToggleComments = function() {
            // Find comment button for the active video
            const v = getActiveVideo();
            let commentBtn = null;
            if (v) {
                const card = v.closest('[data-e2e="feed-item"]') ||
                             v.closest('[class*="DivItemContainer"]') ||
                             v.closest('[class*="DivVideoItemContainer"]');
                if (card) {
                    commentBtn = card.querySelector('button[data-e2e="comment-icon"]') ||
                                 card.querySelector('span[data-e2e="comment-icon"]') ||
                                 card.querySelector('[data-e2e="feed-comment-icon"]');
                }
            }
            if (!commentBtn) {
                commentBtn = document.querySelector('button[data-e2e="comment-icon"]') ||
                             document.querySelector('span[data-e2e="comment-icon"]') ||
                             document.querySelector('[data-e2e="feed-comment-icon"]');
            }
            if (commentBtn) {
                commentBtn.click();
            }
        };

        window.tokmacSetAutoNext = function(enabled) {
            autoPlayNext = enabled;
        };

        // Extract video direct download URL or blob
        window.tokmacGetVideoDownloadInfo = function() {
            const v = getActiveVideo();
            if (!v) return null;

            let downloadUrl = null;
            let src = v.currentSrc || v.src;

            // 1. Direct http URL
            if (src && src.startsWith('http')) {
                downloadUrl = src;
            }

            // 2. Source tags
            if (!downloadUrl) {
                const sources = v.querySelectorAll('source');
                for (const s of sources) {
                    if (s.src && s.src.startsWith('http')) {
                        downloadUrl = s.src;
                        break;
                    }
                }
            }

            // 3. Search Universal Data
            if (!downloadUrl) {
                try {
                    const uData = window.__UNIVERSAL_DATA_FOR_REHYDRATION__;
                    if (uData) {
                        function search(obj) {
                            if (!obj || downloadUrl) return;
                            if (typeof obj === 'object') {
                                if (obj.downloadAddr) {
                                    downloadUrl = obj.downloadAddr;
                                } else if (obj.playAddr) {
                                    downloadUrl = obj.playAddr;
                                }
                                if (!downloadUrl) {
                                    for (const k in obj) search(obj[k]);
                                }
                            }
                        }
                        search(uData);
                    }
                } catch(e) {}
            }

            // 4. Fallback to blob if MSE is used
            if (!downloadUrl && src && src.startsWith('blob:')) {
                downloadUrl = src;
            }

            // Author and description
            const authorEl = document.querySelector('h3[data-e2e="browse-user-title"]') ||
                             document.querySelector('span[data-e2e="browse-user-title"]') ||
                             document.querySelector('span[data-e2e="user-title"]') ||
                             document.querySelector('a[data-e2e="video-author-uniqueid"]');
            const author = authorEl ? authorEl.innerText.trim() : 'TikTok';

            return {
                url: downloadUrl,
                author: author,
                isBlob: downloadUrl ? downloadUrl.startsWith('blob:') : false
            };
        };

        // Download blob via browser FileReader and dispatch to Swift
        window.tokmacDownloadBlob = function(blobUrl, filename) {
            fetch(blobUrl)
                .then(r => r.blob())
                .then(blob => {
                    const reader = new FileReader();
                    reader.onloadend = function() {
                        const base64data = reader.result;
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tokmac) {
                            window.webkit.messageHandlers.tokmac.postMessage({
                                type: 'saveBase64Video',
                                base64: base64data,
                                filename: filename
                            });
                        }
                    };
                    reader.readAsDataURL(blob);
                })
                .catch(err => {
                    console.error("Blob download error:", err);
                });
        };

        // Monitor comment panel state
        function checkCommentPanel() {
            const commentPanel = document.querySelector('[class*="DivCommentContainer"]') ||
                                 document.querySelector('[data-e2e="comment-list"]') ||
                                 document.querySelector('[class*="DivCommentListContainer"]') ||
                                 document.querySelector('[class*="DivCommentItemContainer"]');
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
        setInterval(checkCommentPanel, 500);

        // Auto next video hook
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
