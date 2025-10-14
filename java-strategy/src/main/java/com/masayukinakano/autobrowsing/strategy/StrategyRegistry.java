package com.masayukinakano.autobrowsing.strategy;

import java.net.URI;
import java.net.URISyntaxException;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

public final class StrategyRegistry {
    private final Map<String, LoadMoreStrategy> strategiesBySiteId = new HashMap<>();
    private final Map<String, LoadMoreStrategy> strategiesByHost = new HashMap<>();
    private LoadMoreStrategy defaultStrategy = new FallbackScrollStrategy();

    public static StrategyRegistry defaultRegistry() {
        StrategyRegistry registry = new StrategyRegistry();
        registry.registerSite("demo-news", new TextMatchStrategy(List.of("Load more", "もっと見る")));
        registry.registerHost("news.example.com", new TextMatchStrategy(List.of("Load more")));
        registry.registerSite("bloomberg", new BloombergStrategy());
        registry.registerHost("www.bloomberg.com", new BloombergStrategy());
        return registry;
    }

    public void registerSite(String siteId, LoadMoreStrategy strategy) {
        strategiesBySiteId.put(Objects.requireNonNull(siteId), Objects.requireNonNull(strategy));
    }

    public void registerHost(String host, LoadMoreStrategy strategy) {
        strategiesByHost.put(Objects.requireNonNull(host), Objects.requireNonNull(strategy));
    }

    public void setDefaultStrategy(LoadMoreStrategy strategy) {
        defaultStrategy = Objects.requireNonNull(strategy);
    }

    public LoadMoreResponse handle(LoadMoreRequest request) {
        LoadMoreStrategy strategy = findStrategy(request);
        return strategy.evaluate(request);
    }

    private LoadMoreStrategy findStrategy(LoadMoreRequest request) {
        if (request.getSiteId() != null && strategiesBySiteId.containsKey(request.getSiteId())) {
            return strategiesBySiteId.get(request.getSiteId());
        }
        String host = extractHost(request.getUrl());
        if (host != null) {
            LoadMoreStrategy strategy = strategiesByHost.get(host);
            if (strategy != null) {
                return strategy;
            }
        }
        return defaultStrategy;
    }

    private String extractHost(String url) {
        if (url == null) {
            return null;
        }
        try {
            return new URI(url).getHost();
        } catch (URISyntaxException e) {
            return null;
        }
    }
}
