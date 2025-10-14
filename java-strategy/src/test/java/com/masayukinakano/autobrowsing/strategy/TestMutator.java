package com.masayukinakano.autobrowsing.strategy;

import java.lang.reflect.Field;

final class TestMutator {
    private TestMutator() {
    }

    static void setField(Object target, String fieldName, Object value) {
        try {
            Field field = target.getClass().getDeclaredField(fieldName);
            field.setAccessible(true);
            field.set(target, value);
        } catch (NoSuchFieldException | IllegalAccessException e) {
            throw new IllegalStateException("Failed to set field " + fieldName, e);
        }
    }
}
