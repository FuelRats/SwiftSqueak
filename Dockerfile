# Stage 1 - Build
FROM swift:6.0 AS build

WORKDIR /build

# Copy dependency manifests first for caching
COPY Package.swift Package.resolved ./
RUN swift package resolve

# Copy source code and build
COPY Sources/ Sources/
RUN swift build -c release

# Compile CSS: concatenate all .css files from Views directory into Public/css/styles.css
RUN mkdir -p Public/css && \
    find Sources/mechasqueak/WebServer/Views/ -name '*.css' | sort | xargs cat > Public/css/styles.css

# Stage 2 - Runtime
FROM swift:6.0-slim

# Install Node.js 20 and chrono-node
RUN apt-get update && \
    apt-get install -y nodejs npm && \
    npm install -g chrono-node && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy release binary from build stage
COPY --from=build /build/.build/release/mechasqueak ./mechasqueak

# Copy runtime assets
COPY localisation/ localisation/
COPY templates/ templates/
COPY regions.json .
COPY namedbodies.json .
COPY --from=build /build/Public/ Public/

# Create data directory for token persistence
RUN mkdir -p /data

# Expose web port (configurable via WEB_PORT)
EXPOSE 8080

CMD ["./mechasqueak"]
