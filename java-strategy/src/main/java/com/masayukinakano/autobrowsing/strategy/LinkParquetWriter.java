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
        .required(PrimitiveTypeName.INT64).named("timestampMillis")
        .named("LinkRecord");

    private static final Pattern SAFE_FILENAME = Pattern.compile("[^a-zA-Z0-9._-]");

    private final Path outputDir;

    private LinkParquetWriter(Path outputDir) throws IOException {
        Objects.requireNonNull(outputDir, "outputDir");
        Files.createDirectories(outputDir);
        this.outputDir = outputDir;
    }

    public static LinkParquetWriter openDefault() {
        try {
            return new LinkParquetWriter(Path.of("links-output"));
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

        List<Group> existing = new ArrayList<>();
        Set<String> known = new HashSet<>();
        if (Files.exists(parquetFile)) {
            try (ParquetReader<Group> reader = ParquetReader.builder(new GroupReadSupport(), new org.apache.hadoop.fs.Path(parquetFile.toUri())).build()) {
                Group record;
                while ((record = reader.read()) != null) {
                    existing.add(record);
                    try {
                        String existingSite = record.getBinary("siteId", 0).toStringUsingUTF8();
                        String href = record.getBinary("href", 0).toStringUsingUTF8();
                        if (!existingSite.isBlank() && !href.isBlank()) {
                            known.add(existingSite + "|" + href);
                        }
                    } catch (Exception ignored) {
                    }
                }
            } catch (IOException e) {
                System.err.println("[strategy] failed to read existing parquet: " + e.getMessage());
            }
        }

        SimpleGroupFactory factory = new SimpleGroupFactory(SCHEMA);
        long timestamp = Instant.now().toEpochMilli();
        boolean added = false;
        for (LinkSnapshot link : links) {
            if (link == null || link.getHref() == null || link.getHref().isBlank()) {
                continue;
            }
            String key = (siteId == null ? "" : siteId) + "|" + link.getHref();
            if (!known.add(key)) {
                continue;
            }
            Group group = factory.newGroup()
                .append("siteId", sanitize(siteId))
                .append("pageUrl", sanitize(pageUrl))
                .append("href", link.getHref())
                .append("text", sanitize(link.getText()))
                .append("timestampMillis", timestamp);
            existing.add(group);
            added = true;
        }

        if (!added) {
            return;
        }

        Configuration conf = new Configuration();
        GroupWriteSupport.setSchema(SCHEMA, conf);
        try (ParquetWriter<Group> writer = ExampleParquetWriter.builder(new org.apache.hadoop.fs.Path(parquetFile.toUri()))
            .withConf(conf)
            .withCompressionCodec(CompressionCodecName.SNAPPY)
            .withWriteMode(ParquetFileWriter.Mode.OVERWRITE)
            .build()) {
            for (Group record : existing) {
                writer.write(record);
            }
        } catch (IOException e) {
            System.err.println("[strategy] failed to persist links: " + e.getMessage());
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
