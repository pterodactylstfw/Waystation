import Foundation

/// Provides the JavaScript source injected into Chrome Web Store pages to replace
/// the "Add to Chrome" button with a native-styled "Add to Safari" (or "✓ Installed") button,
/// hide browser incompatibility warning banners, hide unsupported Themes tabs, and communicate with Swift.
enum WebStoreScript {
    static let scriptSource: String = """
    (function() {
        if (window.__waystationInjected) return;
        window.__waystationInjected = true;

        const EXTENSION_ID_REGEX = /[a-z]{32}/;

        // Mock Chrome runtime and userAgentData so Web Store treats browser as genuine modern Google Chrome
        if (!window.chrome) {
            window.chrome = {
                app: { isInstalled: false },
                webstore: {},
                runtime: {
                    PlatformOs: { MAC: 'mac' },
                    PlatformArch: { ARM64: 'arm64' }
                }
            };
        }

        if (!navigator.userAgentData) {
            try {
                Object.defineProperty(navigator, 'userAgentData', {
                    get: () => ({
                        brands: [
                            { brand: 'Google Chrome', version: '131' },
                            { brand: 'Chromium', version: '131' },
                            { brand: 'Not_A Brand', version: '24' }
                        ],
                        mobile: false,
                        platform: 'macOS',
                        getHighEntropyValues: () => Promise.resolve({
                            architecture: 'arm',
                            bitness: '64',
                            model: '',
                            platformVersion: '15.0.0',
                            uaFullVersion: '131.0.0.0'
                        })
                    }),
                    configurable: true
                });
            } catch (e) {}
        }

        // Auto-redirect away from Themes catalog to Extensions catalog
        if (window.location.pathname.includes('/category/themes')) {
            window.location.replace('https://chromewebstore.google.com/category/extensions');
            return;
        }

        // Ensure all target="_blank" links open in current window
        document.addEventListener('click', function(e) {
            const anchor = e.target && e.target.closest ? e.target.closest('a') : null;
            if (anchor && anchor.getAttribute('target') === '_blank') {
                anchor.removeAttribute('target');
            }
        }, true);

        // Keep window.open navigations inside this webview
        const origOpen = window.open;
        window.open = function(url) {
            if (url && typeof url === 'string' && url !== '' && url !== 'about:blank') {
                window.location.href = url;
                return window;
            }
            return origOpen.apply(this, arguments);
        };

        function getExtensionId() {
            const match = window.location.pathname.match(EXTENSION_ID_REGEX);
            return match ? match[0] : null;
        }

        function getExtensionSlug() {
            const parts = window.location.pathname.split('/');
            const detailIdx = parts.indexOf('detail');
            if (detailIdx !== -1 && parts[detailIdx + 1] && parts[detailIdx + 1].length > 0 && parts[detailIdx + 1].length !== 32) {
                return parts[detailIdx + 1].toLowerCase().replace(/[^a-z0-9]/g, '');
            }
            return null;
        }

        function isThemePage() {
            const path = window.location.pathname.toLowerCase();
            if (path.includes('/category/themes')) return true;

            const themeSubcategories = document.querySelectorAll('a[href*="/category/themes/"]');
            if (themeSubcategories.length > 0) return true;

            const themeCollections = document.querySelectorAll('a[href*="collection/chrome_themes"]');
            if (themeCollections.length > 0) return true;

            const categoryLinks = document.querySelectorAll('a[href*="category/themes"]');
            for (const link of categoryLinks) {
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
            const slug = getExtensionSlug();
            const h1 = document.querySelector('h1');
            if (h1 && h1.textContent.trim()) {
                const text = h1.textContent.trim();
                const cleanH1 = text.toLowerCase().replace(/[^a-z0-9]/g, '');
                // Verify that h1 matches the current URL slug rather than being leftover from previous SPA page
                if (!slug || cleanH1.includes(slug) || slug.includes(cleanH1)) {
                    if (!text.toLowerCase().includes('welcome') && !text.toLowerCase().includes('chrome web store')) {
                        return text;
                    }
                }
            }

            const parts = window.location.pathname.split('/');
            const detailIdx = parts.indexOf('detail');
            if (detailIdx !== -1 && parts[detailIdx + 1] && parts[detailIdx + 1].length > 0 && parts[detailIdx + 1].length !== 32) {
                return parts[detailIdx + 1].split('-').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
            }

            return 'Chrome Extension';
        }

        function isCurrentExtensionInstalled() {
            if (!window.__waystationInstalled) return false;
            const names = window.__waystationInstalled.names || [];
            const ids = window.__waystationInstalled.ids || [];

            const currentSlug = getExtensionSlug();
            const currentExtId = (getExtensionId() || '').toLowerCase();

            for (const id of ids) {
                const cleanId = id.toLowerCase().replace(/[^a-z0-9]/g, '');
                if (cleanId && currentSlug && (cleanId === currentSlug || currentSlug.includes(cleanId) || cleanId.includes(currentSlug))) {
                    return true;
                }
                if (cleanId && currentExtId && cleanId === currentExtId) {
                    return true;
                }
            }

            for (const n of names) {
                const cleanN = n.toLowerCase().replace(/[^a-z0-9]/g, '');
                if (cleanN && currentSlug && (cleanN === currentSlug || currentSlug.includes(cleanN) || cleanN.includes(currentSlug))) {
                    return true;
                }
            }
            return false;
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

        // Global capture-phase click listener: guarantees immediate execution on the very first click
        function handleInstallClick(e) {
            const btn = e.target && e.target.closest ? e.target.closest('button, [role="button"]') : null;
            if (!btn) return;

            const text = (btn.textContent || '').trim().toLowerCase();
            const matches = text.includes('add to safari') ||
                            text.includes('add to chrome') ||
                            text.includes('adaugă în chrome') ||
                            text.includes('adăugați în chrome') ||
                            btn.dataset.waystationRole === 'install';

            if (matches) {
                if (isThemePage()) return;
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
                triggerSwiftInstall();
            }
        }

        document.addEventListener('click', handleInstallClick, true);

        function setButtonText(btn, label) {
            if (btn.textContent && btn.textContent.trim() === label) return;

            const descendants = btn.querySelectorAll('*');
            let textSet = false;
            for (const el of descendants) {
                if (el.children.length === 0 && el.textContent && el.textContent.trim().length > 0) {
                    el.textContent = label;
                    textSet = true;
                }
            }
            if (!textSet) {
                for (const node of btn.childNodes) {
                    if (node.nodeType === 3 && node.textContent.trim().length > 0) {
                        node.textContent = label;
                        textSet = true;
                    }
                }
            }
            if (!textSet) {
                btn.textContent = label;
            }
        }

        function hideUnavailableBanners() {
            if (!window.location.pathname.includes('/detail/')) return;

            const candidates = document.querySelectorAll('a, button, span, p, div');
            for (const el of candidates) {
                // Focus on leaf elements
                if (el.children.length > 2) continue;

                const txt = (el.textContent || '').trim().toLowerCase();
                if (txt === 'view guide' ||
                    txt === 'vezi ghidul' ||
                    txt.includes('view guide') ||
                    txt.includes('vezi ghidul') ||
                    txt.includes('item currently unavailable') ||
                    txt.includes('currently unavailable') ||
                    txt.includes('troubleshooting guide') ||
                    txt.includes('ghidul de remediere') ||
                    txt.includes('nu este disponibil')) {

                    let box = el;
                    while (box && box.parentElement &&
                           !box.parentElement.querySelector('h1') &&
                           box.parentElement !== document.body &&
                           box.parentElement.tagName !== 'MAIN') {
                        box = box.parentElement;
                    }

                    if (box && !box.querySelector('h1')) {
                        box.style.setProperty('display', 'none', 'important');
                        box.style.setProperty('height', '0px', 'important');
                        box.style.setProperty('min-height', '0px', 'important');
                        box.style.setProperty('margin', '0px', 'important');
                        box.style.setProperty('padding', '0px', 'important');
                        box.style.setProperty('visibility', 'hidden', 'important');
                        box.style.setProperty('overflow', 'hidden', 'important');
                    }
                }
            }
        }

        function applyReplacements() {
            if (window.location.pathname.includes('/category/themes')) {
                window.location.replace('https://chromewebstore.google.com/category/extensions');
                return;
            }

            if (!window.location.pathname.includes('/detail/')) {
                return;
            }

            hideUnavailableBanners();

            const isTheme = isThemePage();
            const isInstalled = isCurrentExtensionInstalled();
            const targetLabel = isTheme ? 'Themes Not Supported' : (isInstalled ? '✓ Installed' : 'Add to Safari');

            const buttons = document.querySelectorAll('button, [role="button"]');
            for (const btn of buttons) {
                const text = (btn.textContent || '').trim().toLowerCase();
                const matches = text.includes('add to chrome') ||
                                text.includes('add to safari') ||
                                text.includes('adaugă în chrome') ||
                                text.includes('adăugați în chrome') ||
                                text.includes('themes not supported') ||
                                text.includes('installed');

                if (matches) {
                    btn.dataset.waystationRole = isTheme ? 'theme' : 'install';

                    // Prevent endless DOM mutation loop if already styled
                    if (btn.dataset.waystationAppliedLabel === targetLabel) {
                        continue;
                    }

                    if (isTheme) {
                        btn.setAttribute('disabled', 'true');
                        btn.style.setProperty('background-color', '#8e8e93', 'important');
                        btn.style.setProperty('cursor', 'not-allowed', 'important');
                        btn.style.setProperty('opacity', '0.6', 'important');
                        setButtonText(btn, targetLabel);
                        btn.dataset.waystationAppliedLabel = targetLabel;
                    } else {
                        btn.removeAttribute('disabled');
                        btn.removeAttribute('aria-disabled');
                        btn.style.setProperty('background-color', isInstalled ? '#34c759' : '#0071e3', 'important');
                        btn.style.setProperty('color', '#ffffff', 'important');
                        btn.style.setProperty('cursor', 'pointer', 'important');
                        btn.style.setProperty('opacity', '1.0', 'important');
                        btn.style.setProperty('pointer-events', 'auto', 'important');

                        setButtonText(btn, targetLabel);
                        btn.dataset.waystationAppliedLabel = targetLabel;
                    }
                }
            }
        }

        window.__waystationUpdateButtons = applyReplacements;

        // Hook into SPA history state navigation
        const origPushState = history.pushState;
        history.pushState = function() {
            origPushState.apply(this, arguments);
            setTimeout(applyReplacements, 50);
            setTimeout(applyReplacements, 200);
            setTimeout(applyReplacements, 500);
        };

        const origReplaceState = history.replaceState;
        history.replaceState = function() {
            origReplaceState.apply(this, arguments);
            setTimeout(applyReplacements, 50);
            setTimeout(applyReplacements, 200);
            setTimeout(applyReplacements, 500);
        };

        window.addEventListener('popstate', () => {
            setTimeout(applyReplacements, 50);
            setTimeout(applyReplacements, 200);
            setTimeout(applyReplacements, 500);
        });

        // MutationObserver to catch SPA updates without triggering recursion loops
        let debounceTimer = null;
        const observer = new MutationObserver(() => {
            if (debounceTimer) clearTimeout(debounceTimer);
            debounceTimer = setTimeout(applyReplacements, 100);
        });

        observer.observe(document.documentElement, {
            childList: true,
            subtree: true
        });

        applyReplacements();
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', applyReplacements);
        }
    })();
    """
}
