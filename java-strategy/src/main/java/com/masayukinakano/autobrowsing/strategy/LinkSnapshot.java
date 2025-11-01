package com.masayukinakano.autobrowsing.strategy;

import com.fasterxml.jackson.annotation.JsonProperty;

public final class LinkSnapshot {

    @JsonProperty("href")
    private String href;

    @JsonProperty("text")
    private String text;

    @JsonProperty("publishedAt")
    private String publishedAt;

    public LinkSnapshot() {
    }

    public String getHref() {
        return href;
    }

    public String getText() {
        return text;
    }

    public String getPublishedAt() {
        return publishedAt;
    }
}
