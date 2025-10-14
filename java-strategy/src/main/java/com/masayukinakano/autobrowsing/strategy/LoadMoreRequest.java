package com.masayukinakano.autobrowsing.strategy;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.Collections;
import java.util.List;

public final class LoadMoreRequest {
    @JsonProperty("siteId")
    private String siteId;

    @JsonProperty("url")
    private String url;

    @JsonProperty("pageHtml")
    private String pageHtml;

    @JsonProperty("visibleButtons")
    private List<ButtonSnapshot> visibleButtons;

    @JsonProperty("links")
    private List<LinkSnapshot> links;

    public LoadMoreRequest() {
    }

    public String getSiteId() {
        return siteId;
    }

    public String getUrl() {
        return url;
    }

    public String getPageHtml() {
        return pageHtml;
    }

    public List<ButtonSnapshot> getVisibleButtons() {
        return visibleButtons == null ? Collections.emptyList() : visibleButtons;
    }

    public List<LinkSnapshot> getLinks() {
        return links == null ? Collections.emptyList() : links;
    }
}
