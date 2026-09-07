import Foundation

/// Provides the JavaScript source injected into Chrome Web Store pages to replace
/// the "Add to Chrome" button with a native-styled "Add to Safari" button,
/// hide browser incompatibility warning banners, and communicate with Swift.
enum WebStoreScript {
    static let scriptSource: String = """
    (function() {
        if (window.__waystationInjected) return;
        window.__waystationInjected = true;

        const EXTENSION_ID_REGEX = /[a-z]{32}/;

        function getExtensionId() {
            const match = window.location.pathname.match(EXTENSION_ID_REGEX);
            return match ? match[0] : null;
        }

        function getExtensionTitle() {
            // Priority 1: Extract URL slug /detail/<slug>/<id>
            const parts = window.location.pathname.split('/');
            const detailIdx = parts.indexOf('detail');
            let fallbackSlug = null;
            if (detailIdx !== -1 && parts[detailIdx + 1] && parts[detailIdx + 1].length > 0 && parts[detailIdx + 1].length !== 32) {
                fallbackSlug = parts[detailIdx + 1].split('-').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
            }

            // Priority 2: Check h1 if not generic
            const h1 = document.querySelector('h1');
            if (h1 && h1.textContent.trim()) {
                const text = h1.textContent.trim();
                if (!text.toLowerCase().includes('welcome') && !text.toLowerCase().includes('chrome web store')) {
                    return text;
                }
            }

            if (fallbackSlug) {
                return fallbackSlug;
            }

            const titleParts = document.title.split(' - Chrome Web Store');
            if (titleParts[0].trim() && !titleParts[0].toLowerCase().includes('welcome') && !titleParts[0].toLowerCase().includes('chrome web store')) {
                return titleParts[0].trim();
            }

            return 'Chrome Extension';
        }

        function triggerSwiftInstall() {
            const extensionId = getExtensionId();
            if (!extensionId) return;
            const title = getExtensionTitle();
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.waystationHandler) {
                window.webkit.messageHandlers.waystationHandler.postMessage({
                    extensionId: extensionId,
                    title: title,
                    url: window.location.href
                });
            }
        }

        function applyReplacements() {
            // 1. Hide Google's "Item currently unavailable" warning banner safely without affecting page content
            const allElements = document.querySelectorAll('div, section');
            for (const el of allElements) {
                if (el.textContent && el.textContent.includes('Item currently unavailable') && !el.querySelector('h1')) {
                    let target = el;
                    while (target.parentElement &&
                           target.parentElement.textContent.includes('Item currently unavailable') &&
                           !target.parentElement.querySelector('h1') &&
                           target.parentElement !== document.body &&
                           target.parentElement !== document.documentElement) {
                        target = target.parentElement;
                    }
                    target.style.setProperty('display', 'none', 'important');
                    target.style.setProperty('height', '0px', 'important');
                    target.style.setProperty('margin', '0px', 'important');
                    target.style.setProperty('padding', '0px', 'important');
                    target.style.setProperty('overflow', 'hidden', 'important');
                }
            }

            // Also check id="i3" directly
            const alertI3 = document.getElementById('i3');
            if (alertI3) {
                alertI3.style.setProperty('display', 'none', 'important');
                alertI3.style.setProperty('height', '0px', 'important');
                alertI3.style.setProperty('margin', '0px', 'important');
                alertI3.style.setProperty('padding', '0px', 'important');
            }

            // 2. Find the "Add to Chrome" button & text span
            const spans = document.querySelectorAll('span.UywwFc-vQzf8d, span');
            for (const span of spans) {
                const text = (span.textContent || '').trim().toLowerCase();
                if (text === 'add to chrome' || text === 'add to safari') {
                    span.textContent = 'Add to Safari';

                    const btn = span.closest('button');
                    if (btn) {
                        btn.removeAttribute('disabled');
                        btn.removeAttribute('aria-disabled');
                        btn.style.setProperty('background-color', '#0071e3', 'important');
                        btn.style.setProperty('color', '#ffffff', 'important');
                        btn.style.setProperty('cursor', 'pointer', 'important');
                        btn.style.setProperty('opacity', '1.0', 'important');
                        btn.style.setProperty('pointer-events', 'auto', 'important');

                        if (!btn.dataset.waystationBound) {
                            btn.dataset.waystationBound = 'true';
                            btn.addEventListener('click', function(e) {
                                e.preventDefault();
                                e.stopPropagation();
                                e.stopImmediatePropagation();
                                triggerSwiftInstall();
                            }, true);
                        }
                    }
                }
            }

            // Also check buttons directly in case span class differed
            const buttons = document.querySelectorAll('button');
            for (const btn of buttons) {
                const text = (btn.textContent || '').trim().toLowerCase();
                if (text.includes('add to chrome')) {
                    btn.removeAttribute('disabled');
                    btn.removeAttribute('aria-disabled');
                    btn.style.setProperty('background-color', '#0071e3', 'important');
                    btn.style.setProperty('color', '#ffffff', 'important');
                    btn.style.setProperty('cursor', 'pointer', 'important');
                    btn.style.setProperty('opacity', '1.0', 'important');
                    btn.style.setProperty('pointer-events', 'auto', 'important');

                    for (const node of btn.childNodes) {
                        if (node.nodeType === 3 && node.textContent.includes('Add to Chrome')) {
                            node.textContent = 'Add to Safari';
                        }
                    }

                    if (!btn.dataset.waystationBound) {
                        btn.dataset.waystationBound = 'true';
                        btn.addEventListener('click', function(e) {
                            e.preventDefault();
                            e.stopPropagation();
                            e.stopImmediatePropagation();
                            triggerSwiftInstall();
                        }, true);
                    }
                }
            }
        }

        // Hook into SPA history state navigation
        const origPushState = history.pushState;
        history.pushState = function() {
            origPushState.apply(this, arguments);
            setTimeout(applyReplacements, 50);
            setTimeout(applyReplacements, 250);
            setTimeout(applyReplacements, 600);
        };

        const origReplaceState = history.replaceState;
        history.replaceState = function() {
            origReplaceState.apply(this, arguments);
            setTimeout(applyReplacements, 50);
            setTimeout(applyReplacements, 250);
            setTimeout(applyReplacements, 600);
        };

        window.addEventListener('popstate', () => {
            setTimeout(applyReplacements, 50);
            setTimeout(applyReplacements, 250);
            setTimeout(applyReplacements, 600);
        });

        // Fast periodic poll ensures immediate reactivity
        setInterval(applyReplacements, 300);

        // Run immediately
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', applyReplacements);
        } else {
            applyReplacements();
        }
    })();
    """
}
