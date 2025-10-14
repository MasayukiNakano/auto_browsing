package com.masayukinakano.autobrowsing.strategy;

import java.util.ArrayList;
import java.util.List;

final class LoadMoreRequestBuilder {
    private String siteId;
    private String url;
    private String pageHtml;
    private List<ButtonSnapshot> visibleButtons = new ArrayList<>();

    LoadMoreRequestBuilder withSiteId(String siteId) {
        this.siteId = siteId;
        return this;
    }

    LoadMoreRequestBuilder withUrl(String url) {
        this.url = url;
        return this;
    }

    LoadMoreRequestBuilder withPageHtml(String pageHtml) {
        this.pageHtml = pageHtml;
        return this;
    }

    LoadMoreRequestBuilder withVisibleButtons(List<ButtonSnapshot> buttons) {
        this.visibleButtons = new ArrayList<>(buttons);
        return this;
    }

    LoadMoreRequest build() {
        LoadMoreRequest request = new LoadMoreRequest();
        TestMutator.setField(request, "siteId", siteId);
        TestMutator.setField(request, "url", url);
        TestMutator.setField(request, "pageHtml", pageHtml);
        TestMutator.setField(request, "visibleButtons", visibleButtons);
        return request;
    }
}
