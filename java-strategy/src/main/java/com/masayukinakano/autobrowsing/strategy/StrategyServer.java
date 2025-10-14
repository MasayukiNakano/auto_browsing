package com.masayukinakano.autobrowsing.strategy;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

public final class StrategyServer {
    private final ObjectMapper mapper;
    private final StrategyRegistry registry;
    private final LinkParquetWriter linkWriter;

    public StrategyServer(ObjectMapper mapper, StrategyRegistry registry, LinkParquetWriter linkWriter) {
        this.mapper = mapper;
        this.registry = registry;
        this.linkWriter = linkWriter;
    }

    public StrategyServer() {
        this(createObjectMapper(), StrategyRegistry.defaultRegistry(), safeOpenDefaultWriter());
    }

    private static LinkParquetWriter safeOpenDefaultWriter() {
        try {
            return LinkParquetWriter.openDefault();
        } catch (Exception e) {
            System.err.println("[strategy] failed to initialise parquet writer: " + e.getMessage());
            return null;
        }
    }

    private static ObjectMapper createObjectMapper() {
        ObjectMapper mapper = new ObjectMapper();
        mapper.configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
        return mapper;
    }

    public static void main(String[] args) throws IOException {
        new StrategyServer().run();
    }

    public void run() throws IOException {
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
             PrintWriter writer = new PrintWriter(System.out, true, StandardCharsets.UTF_8)) {

            writer.println(safeGreeting());

            String line;
            while ((line = reader.readLine()) != null) {
                String trimmed = line.trim();
                if (trimmed.isEmpty()) {
                    continue;
                }
                if ("quit".equalsIgnoreCase(trimmed)) {
                    writer.println(safeShutdown());
                    break;
                }
                writer.println(handleRequest(trimmed));
            }
        }
        if (linkWriter != null) {
            linkWriter.close();
        }
    }

    private String handleRequest(String jsonLine) {
        try {
            LoadMoreRequest request = mapper.readValue(jsonLine, LoadMoreRequest.class);
            if (linkWriter != null) {
                try {
                    linkWriter.writeLinks(request.getSiteId(), request.getUrl(), request.getLinks());
                } catch (Exception linkError) {
                    System.err.println("[strategy] failed to persist links: " + linkError.getMessage());
                }
            }
            LoadMoreResponse response = registry.handle(request);
            return mapper.writeValueAsString(response);
        } catch (Exception ex) {
            return encodeError(ex.getMessage());
        }
    }

    private String safeGreeting() {
        try {
            return encodeGreeting();
        } catch (JsonProcessingException e) {
            return encodeError(e.getMessage());
        }
    }

    private String safeShutdown() {
        try {
            return encodeShutdown();
        } catch (JsonProcessingException e) {
            return encodeError(e.getMessage());
        }
    }

    private String encodeGreeting() throws JsonProcessingException {
        Map<String, Object> payload = new HashMap<>();
        payload.put("event", "hello");
        payload.put("name", "load-more-strategy");
        payload.put("timestamp", Instant.now().toString());
        return mapper.writeValueAsString(payload);
    }

    private String encodeShutdown() throws JsonProcessingException {
        Map<String, Object> payload = new HashMap<>();
        payload.put("event", "shutdown");
        payload.put("timestamp", Instant.now().toString());
        return mapper.writeValueAsString(payload);
    }

    private String encodeError(String message) {
        try {
            return mapper.writeValueAsString(LoadMoreResponse.error(message));
        } catch (JsonProcessingException e) {
            return "{\"success\":false,\"action\":\"ERROR\",\"message\":\"" + sanitize(message) + "\"}";
        }
    }

    private String sanitize(String message) {
        if (message == null) {
            return "unknown";
        }
        return message.replace('"', '`');
    }
}
