import Foundation

enum CleanupScripts {
    static func script(for key: String) -> String? {
        switch key {
        case "bloombergCleanup":
            return bloomberg
        default:
            return nil
        }
    }

    private static let bloomberg = """
    (function cleanupBloombergByClass() {
        try {
            const LIMIT = 40;
            const candidates = Array.from(document.querySelectorAll('div[class^="styles_itemContainer"]'));
            const visible = candidates.filter(node => node && node.offsetParent !== null);
            if (visible.length <= LIMIT) {
                return JSON.stringify({
                    removed: 0,
                    visibleBefore: visible.length,
                    limit: LIMIT
                });
            }
            const excess = visible.slice(0, visible.length - LIMIT);
            excess.forEach(node => {
                const container = node.closest('div[class^="styles_itemContainer"]') || node;
                container.remove();
            });
            return JSON.stringify({
                removed: excess.length,
                visibleBefore: visible.length,
                limit: LIMIT
            });
        } catch (err) {
            return JSON.stringify({
                removed: 0,
                error: (err && err.message) ? String(err.message) : String(err)
            });
        }
    })();
    """
}
