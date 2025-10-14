package com.masayukinakano.autobrowsing.strategy;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

@JsonInclude(JsonInclude.Include.NON_NULL)
public final class AccessibilityQuery {
    @JsonProperty("titleContains")
    private final String titleContains;

    @JsonProperty("role")
    private final String role;

    public AccessibilityQuery(String titleContains, String role) {
        this.titleContains = titleContains;
        this.role = role;
    }

    public static AccessibilityQuery titleContains(String title) {
        return new AccessibilityQuery(title, null);
    }

    public String getTitleContains() {
        return titleContains;
    }

    public String getRole() {
        return role;
    }
}
