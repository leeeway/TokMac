import Foundation

enum InjectedScripts {
    static let cleanModeCSS = """
    /* TokMac Clean & Streamlined CSS */

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

    /* Completely hide clunky sidebar in compact mode - no black bar! */
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

    /* Reset leftover margins and paddings on feed wrappers to eliminate left black gap */
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
    }

    /* Center video feed nicely in compact portrait view */
    body.tokmac-compact:not(.tokmac-in-detail) [class*="DivItemContainer"],
    body.tokmac-compact:not(.tokmac-in-detail) [class*="DivItemContainerV2"],
    body.tokmac-compact:not(.tokmac-in-detail) [class*="DivVideoItemContainer"] {
        display: flex !important;
        justify-content: center !important;
        align-items: flex-end !important;
        margin: 0 auto !important;
        box-sizing: border-box !important;
    }

    /* Ensure Like, Comment, Share buttons stay clearly visible */
    [class*="DivActionItemContainer"],
    [class*="DivActionContainer"],
    [data-e2e="feed-action-item"] {
        z-index: 100 !important;
        margin-left: 10px !important;
        opacity: 1 !important;
        visibility: visible !important;
    }

    /* Video Detail / Comment Modal: Let it expand naturally without being crushed */
    body.tokmac-in-detail [class*="DivModalContainer"],
    body.tokmac-in-detail [class*="DivFlexCenterRow"],
    body.tokmac-in-detail [class*="DivContentContainer"] {
        width: 100% !important;
        max-width: 100% !important;
        display: flex !important;
        flex-direction: row !important;
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

        console.log("[TokMac] Injected script v3 initialized.");

        let autoPlayNext = false;
        let lastInDetail = false;

        // Force enable native Right-Click Context Menu
        window.addEventListener('contextmenu', function(e) {
            e.stopImmediatePropagation();
        }, true);

        // Navigation buttons helpers
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

        // Monitor whether user is viewing a video detail / comment modal
        function checkDetailAndCommentState() {
            const hasModal = document.querySelector('[class*="DivModalContainer"]') !== null;
            const isVideoUrl = window.location.pathname.includes('/video/');
            const inDetail = hasModal || isVideoUrl;

            document.body.classList.toggle('tokmac-in-detail', inDetail);

            if (inDetail !== lastInDetail) {
                lastInDetail = inDetail;
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tokmac) {
                    window.webkit.messageHandlers.tokmac.postMessage({
                        type: 'detailViewChanged',
                        isOpen: inDetail
                    });
                }
            }
        }
        setInterval(checkDetailAndCommentState, 400);

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
