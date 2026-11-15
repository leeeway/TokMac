import Foundation

enum InjectedScripts {
    static let cleanModeCSS = """
    /* TokMac Clean & Lightweight CSS */

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
    }
    """

    static let keyboardAndNavigationJS = """
    (function() {
        if (window.__tokmac_injected) return;
        window.__tokmac_injected = true;

        console.log("[TokMac] Clean script v5 initialized.");

        // Allow native right click on all elements including video
        window.addEventListener('contextmenu', function(e) {
            e.stopImmediatePropagation();
        }, true);

        // Active video finder
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

        // Video Download URL & Stream Extraction
        window.tokmacGetVideoDownloadInfo = function() {
            const v = getActiveVideo();
            if (!v) return null;

            let downloadUrl = null;
            let src = v.currentSrc || v.src;

            if (src && src.startsWith('http')) {
                downloadUrl = src;
            }

            if (!downloadUrl) {
                const sources = v.querySelectorAll('source');
                for (const s of sources) {
                    if (s.src && s.src.startsWith('http')) {
                        downloadUrl = s.src;
                        break;
                    }
                }
            }

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

        // Download blob stream via FileReader to Base64
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
    })();
    """
}
