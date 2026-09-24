import Foundation

/// Provides the JavaScript source injected into Chrome Web Store pages to replace
/// the "Add to Chrome" button with a native-styled "Add to Safari" button,
/// hide browser incompatibility warning banners, hide unsupported Themes tabs, and communicate with Swift.
enum WebStoreScript {
    static let scriptSource: String = """
    (function() {
        if (window.__waystationInjected) return;
        window.__waystationInjected = true;

        const EXTENSION_ID_REGEX = /[a-z]{32}/;

        // Auto-redirect away from Themes catalog to Extensions catalog
        if (window.location.pathname.includes('/category/themes')) {
            window.location.replace('https://chromewebstore.google.com/category/extensions');
            return;
        }

        // Inject global CSS rule to permanently hide Themes navigation tabs, links, and sections
        const styleId = 'waystation-clean-styles';
        if (!document.getElementById(styleId)) {
            const style = document.createElement('style');
            style.id = styleId;
            style.textContent = `
                a[href*="/category/themes"],
                a[href*="category/themes"],
                [role="tab"]:has(a[href*="/category/themes"]),
                [role="tab"]:has(a[href*="category/themes"]),
                li:has(a[href*="/category/themes"]),
                li:has(a[href*="category/themes"]),
                div:has(> a[href*="/category/themes"]) {
                    display: none !important;
                    visibility: hidden !important;
                    pointer-events: none !important;
                    width: 0 !important;
                    height: 0 !important;
                    margin: 0 !important;
                    padding: 0 !important;
                    overflow: hidden !important;
                }
            `;
            if (document.head) {
                document.head.appendChild(style);
            } else {
                document.addEventListener('DOMContentLoaded', () => {
                    if (document.head && !document.getElementById(styleId)) {
                        document.head.appendChild(style);
                    }
                });
            }
        }

        function getExtensionId() {
            const match = window.location.pathname.match(EXTENSION_ID_REGEX);
            return match ? match[0] : null;
        }

        function isThemePage() {
            const path = window.location.pathname.toLowerCase();
            if (path.includes('/category/themes')) return true;

            // Check if item specifically belongs to theme categories or collections
            const themeSubcategories = document.querySelectorAll('a[href*="/category/themes/"]');
            if (themeSubcategories.length > 0) return true;

            const themeCollections = document.querySelectorAll('a[href*="collection/chrome_themes"]');
            if (themeCollections.length > 0) return true;

            const categoryLinks = document.querySelectorAll('a[href*="category/themes"]');
            for (const link of categoryLinks) {
                // Ignore top navigation tabs or header menu items
                if (link.closest('header, nav, [role="navigation"], [role="tab"], [role="tablist"]')) {
                    continue;
                }
                const text = (link.textContent || '').trim().toLowerCase();
                if (text === 'theme') {
                    return true;
                }
            }
            return false;
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
            if (isThemePage()) return;
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
            // Check for themes URL and redirect
            if (window.location.pathname.includes('/category/themes')) {
                window.location.replace('https://chromewebstore.google.com/category/extensions');
                return;
            }

            // 1. Hide Themes tab links and parent elements
            const themeLinks = document.querySelectorAll('a[href*="/category/themes"], a[href*="category/themes"]');
            for (const link of themeLinks) {
                let container = link.closest('li, [role="tab"], div[role="tab"], div.mUIrbf, div.VfPpkd-dgl27d');
                if (container) {
                    container.style.setProperty('display', 'none', 'important');
                } else {
                    link.style.setProperty('display', 'none', 'important');
                }
            }

            // 2. Hide Google's "Item currently unavailable" warning banner safely without affecting page content
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

            const isTheme = isThemePage();

            // 3. Find the "Add to Chrome" button & text span
            const spans = document.querySelectorAll('span.UywwFc-vQzf8d, span');
            for (const span of spans) {
                const text = (span.textContent || '').trim().toLowerCase();
                if (text === 'add to chrome' || text === 'add to safari' || text === 'themes not supported') {
                    if (isTheme) {
                        span.textContent = 'Themes Not Supported';
                        const btn = span.closest('button');
                        if (btn) {
                            btn.setAttribute('disabled', 'true');
                            btn.style.setProperty('background-color', '#8e8e93', 'important');
                            btn.style.setProperty('cursor', 'not-allowed', 'important');
                            btn.style.setProperty('opacity', '0.6', 'important');
                        }
                    } else {
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
            }

            // Also check buttons directly in case span class differed
            const buttons = document.querySelectorAll('button');
            for (const btn of buttons) {
                const text = (btn.textContent || '').trim().toLowerCase();
                if (text.includes('add to chrome') || text.includes('add to safari') || text.includes('themes not supported')) {
                    if (isTheme) {
                        btn.setAttribute('disabled', 'true');
                        btn.style.setProperty('background-color', '#8e8e93', 'important');
                        btn.style.setProperty('cursor', 'not-allowed', 'important');
                        btn.style.setProperty('opacity', '0.6', 'important');
                        for (const node of btn.childNodes) {
                            if (node.nodeType === 3 && (node.textContent.includes('Add to Chrome') || node.textContent.includes('Add to Safari'))) {
                                node.textContent = 'Themes Not Supported';
                            }
                        }
                    } else {
                        btn.removeAttribute('disabled');
                        btn.removeAttribute('aria-disabled');
                        btn.style.setProperty('background-color', '#0071e3', 'important');
                        btn.style.setProperty('color', '#ffffff', 'important');
                        btn.style.setProperty('cursor', 'pointer', 'important');
                        btn.style.setProperty('opacity', '1.0', 'important');
                        btn.style.setProperty('pointer-events', 'auto', 'important');

                        for (const node of btn.childNodes) {
                            if (node.nodeType === 3 && (node.textContent.includes('Add to Chrome') || node.textContent.includes('Themes Not Supported'))) {
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
