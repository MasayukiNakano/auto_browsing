package com.masayukinakano.autobrowsing.strategy;

public final class FallbackScrollStrategy implements LoadMoreStrategy {
    private final double scrollDistance;

    public FallbackScrollStrategy() {
        this(-480);
    }

    public FallbackScrollStrategy(double scrollDistance) {
        this.scrollDistance = scrollDistance;
    }

    @Override
    public LoadMoreResponse evaluate(LoadMoreRequest request) {
        return LoadMoreResponse.scroll(scrollDistance);
    }
}
