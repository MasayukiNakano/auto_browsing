package com.masayukinakano.autobrowsing.strategy;

import com.fasterxml.jackson.annotation.JsonProperty;

public final class LinkSnapshot {

    @JsonProperty("href")
    private String href;

    @JsonProperty("text")
    private String text;

    public LinkSnapshot() {
    }

    public String getHref() {
        return href;
    }

    public String getText() {
        return text;
    }
}
