package com.masayukinakano.autobrowsing.strategy;

import java.util.List;
import java.util.Locale;

public final class BloombergStrategy implements LoadMoreStrategy {

    private static final List<String> KEYWORDS = List.of(
        "load more",
        "more stories",
        "more articles",
        "さらに表示",
        "もっと読む"
    );

    @Override
    public LoadMoreResponse evaluate(LoadMoreRequest request) {
        for (ButtonSnapshot button : request.getVisibleButtons()) {
            if (button.getTitle() == null && button.getRole() == null) {
                continue;
            }
            if (!"AXButton".equals(button.getRole())) {
                continue;
            }
            if (matches(button.getTitle())) {
                return LoadMoreResponse.press(AccessibilityQuery.titleContains("more"));
            }
        }
        return LoadMoreResponse.scroll( -600);
    }

    private boolean matches(String text) {
        if (text == null) {
            return false;
        }
        String lower = text.toLowerCase(Locale.ROOT);
        return KEYWORDS.stream().anyMatch(lower::contains);
    }
}
