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
        innerWidth: 1000, innerHeight: 800, addEventListener() {}, scrollBy() {},
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
