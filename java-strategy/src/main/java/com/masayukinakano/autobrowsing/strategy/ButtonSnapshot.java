package com.masayukinakano.autobrowsing.strategy;

import com.fasterxml.jackson.annotation.JsonProperty;

public final class ButtonSnapshot {
    @JsonProperty("title")
    private String title;

    @JsonProperty("role")
    private String role;

    public ButtonSnapshot() {
    }

    public ButtonSnapshot(String title, String role) {
        this.title = title;
        this.role = role;
    }

    public String getTitle() {
        return title;
    }

    public String getRole() {
        return role;
    }
}
