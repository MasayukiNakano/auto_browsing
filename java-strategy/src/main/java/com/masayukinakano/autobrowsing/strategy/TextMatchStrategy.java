package com.masayukinakano.autobrowsing.strategy;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Objects;

public final class TextMatchStrategy implements LoadMoreStrategy {
    private final List<String> phrases;

    public TextMatchStrategy(List<String> phrases) {
        this.phrases = new ArrayList<>(Objects.requireNonNull(phrases));
    }

    @Override
    public LoadMoreResponse evaluate(LoadMoreRequest request) {
        for (ButtonSnapshot button : request.getVisibleButtons()) {
            String title = button.getTitle();
            if (title == null) {
                continue;
            }
            for (String phrase : phrases) {
                if (title.toLowerCase(Locale.JAPANESE).contains(phrase.toLowerCase(Locale.JAPANESE))) {
                    return LoadMoreResponse.press(AccessibilityQuery.titleContains(title));
                }
            }
        }
        return LoadMoreResponse.none("No matching button text found");
    }
}
