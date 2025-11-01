package com.masayukinakano.autobrowsing.strategy;

import java.io.Closeable;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;
import java.util.regex.Pattern;
import org.apache.hadoop.conf.Configuration;
import org.apache.parquet.example.data.Group;
import org.apache.parquet.example.data.simple.SimpleGroupFactory;
import org.apache.parquet.hadoop.ParquetFileWriter;
import org.apache.parquet.hadoop.ParquetReader;
import org.apache.parquet.hadoop.ParquetWriter;
import org.apache.parquet.hadoop.example.ExampleParquetWriter;
import org.apache.parquet.hadoop.example.GroupReadSupport;
import org.apache.parquet.hadoop.example.GroupWriteSupport;
import org.apache.parquet.hadoop.metadata.CompressionCodecName;
import org.apache.parquet.schema.MessageType;
import org.apache.parquet.schema.OriginalType;
import org.apache.parquet.schema.PrimitiveType.PrimitiveTypeName;
import org.apache.parquet.schema.Types;

public final class LinkParquetWriter implements Closeable {

    private static final MessageType SCHEMA = Types.buildMessage()
        .required(PrimitiveTypeName.BINARY).as(OriginalType.UTF8).named("siteId")
        .optional(PrimitiveTypeName.BINARY).as(OriginalType.UTF8).named("pageUrl")
        .required(PrimitiveTypeName.BINARY).as(OriginalType.UTF8).named("href")
        .optional(PrimitiveTypeName.BINARY).as(OriginalType.UTF8).named("text")
        .optional(PrimitiveTypeName.BINARY).as(OriginalType.UTF8).named("publishedAt")
        .required(PrimitiveTypeName.INT64).named("timestampMillis")
        .named("LinkRecord");

    private static final Pattern SAFE_FILENAME = Pattern.compile("[^a-zA-Z0-9._-]");

    private static final class LinkRecord {
        private final String siteId;
        private final String pageUrl;
        private final String href;
        private final String text;
        private final String publishedAt;
        private final long timestampMillis;

        private LinkRecord(String siteId, String pageUrl, String href, String text, String publishedAt, long timestampMillis) {
            this.siteId = siteId;
            this.pageUrl = pageUrl;
            this.href = href;
            this.text = text;
            this.publishedAt = publishedAt;
            this.timestampMillis = timestampMillis;
        }
    }

    private final Path outputDir;
    private final Set<Path> loggedExistingFiles = new HashSet<>();

    private LinkParquetWriter(Path outputDir) throws IOException {
        Objects.requireNonNull(outputDir, "outputDir");
        Files.createDirectories(outputDir);
        this.outputDir = outputDir;
        System.err.println("[strategy] link output directory: " + outputDir.toAbsolutePath());
    }

    public static LinkParquetWriter openDefault() {
        try {
            String override = System.getenv("AUTO_BROWSING_LINKS_OUTPUT");
            Path basePath;
            if (override != null && !override.trim().isEmpty()) {
                basePath = Path.of(override.trim()).toAbsolutePath();
            } else {
                basePath = Path.of("links-output");
            }
            return new LinkParquetWriter(basePath);
        } catch (IOException e) {
            throw new IllegalStateException("Failed to create output directory", e);
        }
    }

    public synchronized void writeLinks(String siteId, String pageUrl, List<LinkSnapshot> links) {
        if (links == null || links.isEmpty()) {
            return;
        }

        String fileKey = buildFileKey(siteId, pageUrl);
        Path parquetFile = outputDir.resolve(fileKey + ".parquet");
        System.err.println("[strategy] resolved parquet path: " + parquetFile.toAbsolutePath());

        List<LinkRecord> records = new ArrayList<>();
        Set<String> known = new HashSet<>();
        if (Files.exists(parquetFile)) {
            if (loggedExistingFiles.add(parquetFile)) {
                System.err.println("[strategy] loading existing links from " + parquetFile.toAbsolutePath());
            }
            try (ParquetReader<Group> reader = ParquetReader.builder(new GroupReadSupport(), new org.apache.hadoop.fs.Path(parquetFile.toUri())).build()) {
                Group record;
                while ((record = reader.read()) != null) {
                    LinkRecord existingRecord = convertGroup(record);
                    if (existingRecord != null) {
                        records.add(existingRecord);
                        if (!existingRecord.siteId.isBlank() && !existingRecord.href.isBlank()) {
                            known.add(existingRecord.siteId + "|" + existingRecord.href);
                        }
                    }
                }
                if (!records.isEmpty()) {
                    System.err.println("[strategy] existing records: " + records.size());
                }
            } catch (IOException e) {
                System.err.println("[strategy] failed to read existing parquet: " + e.getMessage());
            }
        }

        long timestamp = Instant.now().toEpochMilli();
        int newRecords = 0;
        for (LinkSnapshot link : links) {
            if (link == null || link.getHref() == null || link.getHref().isBlank()) {
                continue;
            }
            String sanitizedSiteId = sanitize(siteId);
            String key = sanitizedSiteId + "|" + link.getHref();
            if (!known.add(key)) {
                continue;
            }
            records.add(new LinkRecord(
                sanitizedSiteId,
                sanitize(pageUrl),
                link.getHref(),
                sanitize(link.getText()),
                sanitize(link.getPublishedAt()),
                timestamp
            ));
            newRecords++;
        }

        System.err.println("[strategy] known map size after load: " + known.size());

        if (newRecords == 0) {
            try {
                writeKnownCache(parquetFile, records);
            } catch (IOException e) {
                System.err.println("[strategy] failed to update known cache: " + e.getMessage());
            }
            return;
        }

        Configuration conf = new Configuration();
        GroupWriteSupport.setSchema(SCHEMA, conf);
        SimpleGroupFactory factory = new SimpleGroupFactory(SCHEMA);
        try (ParquetWriter<Group> writer = ExampleParquetWriter.builder(new org.apache.hadoop.fs.Path(parquetFile.toUri()))
            .withConf(conf)
            .withCompressionCodec(CompressionCodecName.SNAPPY)
            .withWriteMode(ParquetFileWriter.Mode.OVERWRITE)
            .build()) {
            for (LinkRecord record : records) {
                Group group = factory.newGroup()
                    .append("siteId", record.siteId)
                    .append("pageUrl", record.pageUrl)
                    .append("href", record.href)
                    .append("text", record.text)
                    .append("publishedAt", record.publishedAt)
                    .append("timestampMillis", record.timestampMillis);
                writer.write(group);
            }
        } catch (IOException e) {
            System.err.println("[strategy] failed to persist links: " + e.getMessage());
            return;
        }

        System.err.println("[strategy] saved " + newRecords + " new links to " + parquetFile.toAbsolutePath());

        try {
            writeKnownCache(parquetFile, records);
        } catch (IOException e) {
            System.err.println("[strategy] failed to update known cache: " + e.getMessage());
        }
    }

    private void writeKnownCache(Path parquetFile, List<LinkRecord> records) throws IOException {
        Path knownFile = parquetFile.resolveSibling(parquetFile.getFileName().toString() + ".known");
        List<String> hrefs = new ArrayList<>(records.size());
        for (LinkRecord record : records) {
            if (record.href != null && !record.href.isBlank()) {
                hrefs.add(record.href);
            }
        }
        Files.writeString(knownFile, String.join("\n", hrefs));
    }

    private LinkRecord convertGroup(Group group) {
        try {
            String siteId = sanitize(safeBinary(group, "siteId"));
            String pageUrl = sanitize(safeBinary(group, "pageUrl"));
            String href = safeBinary(group, "href");
            String text = sanitize(safeBinary(group, "text"));
            String publishedAt = sanitize(safeBinary(group, "publishedAt"));
            long timestamp;
            try {
                timestamp = group.getLong("timestampMillis", 0);
            } catch (Exception ex) {
                timestamp = Instant.now().toEpochMilli();
            }
            if (href.isBlank()) {
                return null;
            }
            return new LinkRecord(siteId, pageUrl, href, text, publishedAt, timestamp);
        } catch (Exception ex) {
            System.err.println("[strategy] skip corrupted parquet row: " + ex.getMessage());
            return null;
        }
    }

    private String safeBinary(Group group, String field) {
        try {
            if (!group.getType().containsField(field)) {
                return "";
            }
            return group.getBinary(field, 0).toStringUsingUTF8();
        } catch (Exception ex) {
            return "";
        }
    }

    private String sanitizeFileName(String value) {
        String sanitized = SAFE_FILENAME.matcher(value).replaceAll("_");
        return sanitized.isBlank() ? "default" : sanitized;
    }

    private String sanitize(String value) {
        return value == null ? "" : value;
    }

    private String buildFileKey(String siteId, String pageUrl) {
        String base = sanitizeFileName(siteId == null || siteId.isBlank() ? "default" : siteId);
        if (pageUrl == null || pageUrl.isBlank()) {
            return base;
        }
        try {
            java.net.URI uri = new java.net.URI(pageUrl);
            String path = uri.getPath();
            if (path != null && !path.isBlank()) {
                for (String segment : path.split("/")) {
                    if (segment == null || segment.isBlank()) {
                        continue;
                    }
                    String sanitizedSegment = sanitizeFileName(segment);
                    if (!sanitizedSegment.isBlank()) {
                        return base + "_" + sanitizedSegment;
                    }
                }
            }
            return base;
        } catch (Exception ignored) {
            return base;
        }
    }

    @Override
    public void close() {
        // no-op
    }
}
