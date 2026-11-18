const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const script = fs.readFileSync(path.join(__dirname, '../Sources/TokMac/Scripts/tokmac.js'), 'utf8');

function fixture({ headReady = true, source = 'blob:https://www.tiktok.com/current', id = null, metadata, host = 'www.tiktok.com', frame = false } = {}) {
    const events = {};
    const styles = [];
    const anchors = [];
    const card = { querySelector(selector) {
        return selector.includes('/video/') && id ? { href: `https://www.tiktok.com/@user/video/${id}` } : null;
    }};
    const video = { currentSrc: source, closest: () => card, querySelectorAll: () => [],
        getBoundingClientRect: () => ({ top: 0, bottom: 800, left: 0, right: 500, width: 500, height: 800 }) };
    const videos = [video];
    const window = {
        location: { protocol: 'https:', hostname: host, origin: `https://${host}`, pathname: '/foryou' },
        innerWidth: 1000, innerHeight: 800, addEventListener: (name, callback) => events[name] = callback, scrollBy() {},
        __UNIVERSAL_DATA_FOR_REHYDRATION__: metadata
    };
    window.top = frame ? {} : window;
    const document = {
        readyState: headReady ? 'complete' : 'loading',
        head: headReady ? { appendChild: style => styles.push(style) } : null,
        documentElement: null,
        body: { appendChild: anchor => anchors.push(anchor) },
        getElementById: () => null,
        createElement: () => ({ click() { this.clicked = true; }, remove() { this.removed = true; } }),
        addEventListener: (name, callback) => events[name] = callback,
        querySelectorAll: () => videos,
        querySelector: () => null
    };
    vm.runInNewContext(script, { window, document, URL });
    return { window, document, styles, anchors, events, video, videos };
}

test('document-created injection registers helpers before head exists, then installs CSS', () => {
    const f = fixture({ headReady: false });
    assert.equal(typeof f.window.tokmacGetVideoDownloadInfo, 'function');
    assert.equal(f.styles.length, 0);
    f.document.head = { appendChild: style => f.styles.push(style) };
    f.events.DOMContentLoaded();
    assert.equal(f.styles[0].id, '__tokmac_clean_style');
});

test('unrelated recommendations never replace the visible Blob source', () => {
    const f = fixture({ metadata: { recommendations: [{ id: '999', video: { downloadAddr: 'https://cdn.example/other.mp4' } }] } });
    assert.equal(f.window.tokmacGetVideoDownloadInfo().url, 'blob:https://www.tiktok.com/current');
});

test('matches the visible video ID rather than the first recommendation', () => {
    const f = fixture({ id: '123', metadata: { recommendations: [
        { id: '999', video: { downloadAddr: 'https://cdn.example/other.mp4' } },
        { id: '123', video: { downloadAddr: 'https://cdn.example/current.mp4' }, author: { uniqueId: "O'Connor" } }
    ] } });
    const info = f.window.tokmacGetVideoDownloadInfo();
    assert.equal(info.url, 'https://cdn.example/current.mp4');
    assert.equal(info.author, "O'Connor");
});

test('uses the actual video source before hydration metadata', () => {
    const f = fixture({ source: 'https://cdn.example/playing.mp4', id: '123', metadata: { id: '123', video: { downloadAddr: 'https://cdn.example/old.mp4' } } });
    assert.equal(f.window.tokmacGetVideoDownloadInfo().url, 'https://cdn.example/playing.mp4');
});

test('cyclic metadata terminates and cannot select an unrelated URL', () => {
    const metadata = { id: '999', video: { downloadAddr: 'https://cdn.example/other.mp4' } };
    metadata.self = metadata;
    const f = fixture({ id: '123', metadata });
    assert.equal(f.window.tokmacGetVideoDownloadInfo().isBlob, true);
});

test('hidden videos are not selected for download', () => {
    const f = fixture();
    f.video.getBoundingClientRect = () => ({ top: 0, bottom: 0, left: 0, right: 0, width: 0, height: 0 });
    assert.equal(f.window.tokmacGetVideoDownloadInfo(), null);
});

test('native Blob download uses DOM properties and handles quotes without script interpolation', () => {
    const f = fixture();
    const url = "blob:https://www.tiktok.com/o'connor";
    f.window.tokmacDownloadBlob(url);
    assert.equal(f.anchors[0].href, url);
    assert.equal(f.anchors[0].clicked, true);
    assert.equal(f.anchors[0].removed, true);
});

test('foreign Blob and non-Blob native download requests are rejected', () => {
    const f = fixture();
    for (const url of ['blob:https://evil.example/id', 'file:///etc/passwd', 'javascript:alert(1)']) {
        assert.throws(() => f.window.tokmacDownloadBlob(url));
    }
    assert.equal(f.anchors.length, 0);
});

test('untrusted pages and subframes receive no native download helpers', () => {
    assert.equal(fixture({ host: 'tiktok.com.evil.example' }).window.tokmacDownloadBlob, undefined);
    assert.equal(fixture({ frame: true }).window.tokmacDownloadBlob, undefined);
});

function keyEvent(key, extra = {}) {
    return { key, target: { closest: () => null }, preventDefault() { this.prevented = true; },
        stopImmediatePropagation() { this.stopped = true; }, ...extra };
}

test('unmodified playback keys work without handling system shortcuts', () => {
    const f = fixture();
    const event = keyEvent('m');
    f.events.keydown(event);
    assert.equal(f.video.muted, true);
    assert.equal(event.prevented, true);
    assert.equal(event.stopped, true);
    for (const key of ['c', 'm', 'a', 'v', 'z']) {
        const system = keyEvent(key, { metaKey: true });
        f.events.keydown(system);
        assert.equal(system.prevented, undefined);
    }
});

test('comments, search fields, editable descendants and IME retain their keys', () => {
    const f = fixture();
    for (const key of [' ', 'm', 'c', 'j', 'ArrowDown']) {
        for (const target of [{ closest: () => ({}) }, { isContentEditable: true, closest: () => null }]) {
            const event = keyEvent(key, { target });
            f.events.keydown(event);
            assert.equal(event.prevented, undefined);
        }
        const composing = keyEvent(key, { isComposing: true });
        f.events.keydown(composing);
        assert.equal(composing.prevented, undefined);
        f.document.activeElement = { isContentEditable: true };
        const focused = keyEvent(key);
        f.events.keydown(focused);
        assert.equal(focused.prevented, undefined);
        f.document.activeElement = null;
    }
    assert.equal(f.video.muted, undefined);
});

test('held playback keys do not repeatedly toggle state', () => {
    const f = fixture();
    f.events.keydown(keyEvent('m'));
    f.events.keydown(keyEvent('m', { repeat: true }));
    assert.equal(f.video.muted, true);
});

test('download and comments target the playing card instead of an edge preview or a different card', () => {
    const f = fixture({ source: 'https://cdn.example/playing.mp4' });
    const clicks = [];
    f.video.paused = false;
    f.video.closest = () => ({ querySelector: selector => selector.includes('feed-comment')
        ? { click() { clicks.push('active'); } } : null });
    const preview = {
        ...f.video, paused: true, currentSrc: 'https://cdn.example/preview.mp4',
        getBoundingClientRect: () => ({ top: 300, bottom: 500, left: 999, right: 1100, width: 101, height: 200 }),
        closest: () => ({ querySelector: selector => selector.includes('feed-comment')
            ? { click() { clicks.push('preview'); } } : null })
    };
    f.videos.unshift(preview);
    f.document.querySelector = () => ({ click() { clicks.push('global'); } });
    assert.equal(f.window.tokmacGetVideoDownloadInfo().url, 'https://cdn.example/playing.mp4');
    f.window.tokmacToggleComments();
    assert.deepEqual(clicks, ['active']);

    f.video.paused = true;
    preview.paused = false;
    assert.equal(f.window.tokmacGetVideoDownloadInfo().url, 'https://cdn.example/playing.mp4');
});

test('a fully visible playing clip wins over a larger paused clip', () => {
    const f = fixture({ source: 'https://cdn.example/paused.mp4' });
    f.video.paused = true;
    f.videos.push({
        ...f.video, paused: false, currentSrc: 'https://cdn.example/playing.mp4',
        getBoundingClientRect: () => ({ top: 100, bottom: 350, left: 600, right: 900, width: 300, height: 250 })
    });
    assert.equal(f.window.tokmacGetVideoDownloadInfo().url, 'https://cdn.example/playing.mp4');
});

test('comments do not fall back to another card when the active card has no button', () => {
    const f = fixture();
    f.videos.push({ ...f.video, paused: true });
    f.document.querySelectorAll = selector => selector === 'video' ? f.videos : [{ click() { assert.fail('wrong card clicked'); } }];
    f.window.tokmacToggleComments();
});

test('next and previous video leave photo carousel buttons alone', () => {
    const f = fixture();
    f.video.closest = () => null;
    const actions = [];
    f.document.querySelector = selector => {
        if (selector.includes('aria-label*="Next"')) return { click: () => actions.push('photo') };
        if (selector.includes('feed-arrow-down')) return { click: () => actions.push('next video') };
        if (selector.includes('feed-arrow-up')) return { click: () => actions.push('previous video') };
        return null;
    };
    f.events.keydown(keyEvent('ArrowDown'));
    f.events.keydown(keyEvent('ArrowUp'));
    assert.deepEqual(actions, ['next video', 'previous video']);
});

test('fallback scrolls the container that owns the active player', () => {
    const f = fixture();
    f.video.closest = () => null;
    const moves = [];
    f.video.parentElement = { scrollHeight: 1200, clientHeight: 600, scrollBy: ({ top }) => moves.push(top) };
    f.window.getComputedStyle = () => ({ overflowY: 'auto' });
    f.window.scrollBy = () => assert.fail('unrelated page scrolled');
    f.window.tokmacNextVideo();
    f.window.tokmacPrevVideo();
    assert.deepEqual(moves, [510, -510]);
});
