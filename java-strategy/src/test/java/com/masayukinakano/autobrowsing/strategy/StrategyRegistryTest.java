package com.masayukinakano.autobrowsing.strategy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import org.junit.jupiter.api.Test;

class StrategyRegistryTest {

    @Test
    void fallbackStrategyProducesScroll() {
        StrategyRegistry registry = StrategyRegistry.defaultRegistry();
        LoadMoreRequest request = new LoadMoreRequestBuilder()
            .withSiteId("unknown")
            .build();
        LoadMoreResponse response = registry.handle(request);
        assertTrue(response.isSuccess());
        assertEquals(StrategyAction.SCROLL, response.getAction());
    }

    @Test
    void textMatchStrategyMatchesKnownPhrase() {
        StrategyRegistry registry = StrategyRegistry.defaultRegistry();
        LoadMoreRequest request = new LoadMoreRequestBuilder()
            .withSiteId("demo-news")
            .withVisibleButtons(List.of(new ButtonSnapshot("Load more", "AXButton")))
            .build();
        LoadMoreResponse response = registry.handle(request);
        assertEquals(StrategyAction.PRESS, response.getAction());
    }
}
