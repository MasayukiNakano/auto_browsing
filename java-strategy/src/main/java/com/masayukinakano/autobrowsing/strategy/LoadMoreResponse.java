package com.masayukinakano.autobrowsing.strategy;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

@JsonInclude(JsonInclude.Include.NON_NULL)
public final class LoadMoreResponse {
    @JsonProperty("success")
    private final boolean success;

    @JsonProperty("action")
    private final StrategyAction action;

    @JsonProperty("message")
    private final String message;

    @JsonProperty("query")
    private final AccessibilityQuery query;

    @JsonProperty("scrollDistance")
    private final Double scrollDistance;

    @JsonProperty("waitSeconds")
    private final Double waitSeconds;

    private LoadMoreResponse(boolean success, StrategyAction action, String message, AccessibilityQuery query,
                             Double scrollDistance, Double waitSeconds) {
        this.success = success;
        this.action = action;
        this.message = message;
        this.query = query;
        this.scrollDistance = scrollDistance;
        this.waitSeconds = waitSeconds;
    }

    public static LoadMoreResponse press(AccessibilityQuery query) {
        return new LoadMoreResponse(true, StrategyAction.PRESS, null, query, null, null);
    }

    public static LoadMoreResponse scroll(double distance) {
        return new LoadMoreResponse(true, StrategyAction.SCROLL, null, null, distance, null);
    }

    public static LoadMoreResponse waitSeconds(double seconds) {
        return new LoadMoreResponse(true, StrategyAction.WAIT, null, null, null, seconds);
    }

    public static LoadMoreResponse none(String message) {
        return new LoadMoreResponse(true, StrategyAction.NO_ACTION, message, null, null, null);
    }

    public static LoadMoreResponse error(String message) {
        return new LoadMoreResponse(false, StrategyAction.ERROR, message, null, null, null);
    }

    public boolean isSuccess() {
        return success;
    }

    public StrategyAction getAction() {
        return action;
    }

    public String getMessage() {
        return message;
    }

    public AccessibilityQuery getQuery() {
        return query;
    }

    public Double getScrollDistance() {
        return scrollDistance;
    }

    public Double getWaitSeconds() {
        return waitSeconds;
    }
}
