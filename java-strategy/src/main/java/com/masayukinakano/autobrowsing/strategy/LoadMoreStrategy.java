package com.masayukinakano.autobrowsing.strategy;

public interface LoadMoreStrategy {
    LoadMoreResponse evaluate(LoadMoreRequest request);
}
