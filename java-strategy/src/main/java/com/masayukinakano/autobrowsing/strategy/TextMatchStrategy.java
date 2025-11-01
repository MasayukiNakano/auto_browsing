package com.masayukinakano.autobrowsing.strategy;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.stream.Collectors;

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
                    System.err.println("[strategy] matched button '" + title + "' for phrase '" + phrase + "'");
                    return LoadMoreResponse.press(AccessibilityQuery.titleContains(title));
                }
            }
        }
        String available = request.getVisibleButtons().stream()
            .map(ButtonSnapshot::getTitle)
            .filter(Objects::nonNull)
            .collect(Collectors.joining(", "));
        System.err.println("[strategy] no matching button found. Available: " + available);
        return LoadMoreResponse.none("No matching button text found");
    }
}
