import Foundation

enum InjectedScripts {
    static let cleanModeCSS = """
    /* TokMac Clean Mode CSS */
    
    /* Hide top nav banner and download banners */
    div[class*="DivBannerContainer"],
    div[class*="DivDownloadLinkContainer"],
    div[class*="DivMobileAppWrapper"],
    div[class*="DivGetAppContainer"],
    div[class*="DivDesktopDownloadPrompt"],
    a[href*="download"],
    div[id*="get-app"],
    div[class*="DivAppBannerContainer"] {
        display: none !important;
    }

    /* In compact/phone view, maximize video container */
    body.tokmac-compact div[class*="DivSideNavContainer"],
    body.tokmac-compact aside,
    body.tokmac-compact header {
        display: none !important;
    }

    body.tokmac-compact div[class*="DivMainContainer"],
    body.tokmac-compact div[class*="DivBodyContainer"],
    body.tokmac-compact div[class*="DivContentContainer"],
    body.tokmac-compact main {
        margin: 0 !important;
        padding: 0 !important;
        width: 100% !important;
        max-width: 100% !important;
        display: flex !important;
        justify-content: center !important;
    }

    /* Hide ugly scrollbar but keep scroll functionality */
    ::-webkit-scrollbar {
        width: 4px;
        height: 4px;
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

        console.log("[TokMac] Injected script active.");

        // State
        let autoPlayNext = false;

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
            // Find video closest to center of screen
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

        window.tokmacSetAutoNext = function(enabled) {
            autoPlayNext = enabled;
            console.log("[TokMac] Auto next:", autoPlayNext);
        };

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
        setInterval(hookVideos, 2000);

        // Global Keyboard Shortcut listener
        window.addEventListener('keydown', function(e) {
            // Do not intercept if user is typing in an input or textarea
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
            }
        }, true);
    })();
    """
}
