# Stage 1 - Build
FROM swift:6.1 AS build

WORKDIR /build

# Copy manifests and source structure for dependency resolution
# (Package.swift enumerates CSS files from Sources/ at manifest parse time)
COPY Package.swift Package.resolved ./
COPY Sources/ Sources/
COPY Tests/ Tests/
RUN swift package resolve

# Build release binary (cache mount target for dev builds)
ARG BUILDKIT_CACHE=""
RUN --mount=type=cache,id=spm-build,target=/build/.build,sharing=locked \
    swift build -c release && \
    cp -a .build/release/mechasqueak /usr/local/bin/mechasqueak

# Compile CSS: concatenate all .css files from Views directory into Public/css/styles.css
RUN mkdir -p Public/css && \
    find Sources/mechasqueak/WebServer/Views/ -name '*.css' | sort | xargs cat > Public/css/styles.css

# Stage 2 - Runtime
FROM swift:6.1-slim

# Install Node.js and chrono-node
RUN apt-get update && \
    apt-get install -y nodejs npm && \
    npm install -g chrono-node && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy release binary from build stage
COPY --from=build /usr/local/bin/mechasqueak ./mechasqueak

# Copy runtime assets
COPY localisation/ localisation/
COPY templates/ templates/
COPY regions.json .
COPY namedbodies.json .
COPY --from=build /build/Public/ Public/

# Create data directory for token persistence
RUN mkdir -p /data

EXPOSE 8080

CMD ["./mechasqueak"]
