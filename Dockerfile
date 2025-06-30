FROM swift:6.1 as builder

WORKDIR /app

COPY . .

RUN echo "public let buildVersion = \"$(date +%Y-%m-%d)-g$(git rev-parse --short HEAD)\"" > Sources/mechasqueak/BuildVersion.swift

RUN swift build

# Copy assets into the build output directory
RUN cp -R localisation .build/debug/ && \
    cp -R templates .build/debug/ && \
    cp -R regions.json .build/debug/ && \
    cp -R namedbodies.json .build/debug/

# Generate the combined styles.css file
RUN mkdir -p Public/css && \
    find Sources/mechasqueak/WebServer/Views -type f -name "*.css" | sort | xargs cat > Public/css/styles.css

FROM swift:6.1-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y curl gnupg unzip && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs gettext

RUN npm install -g chrono-node

# Copy compiled binary and runtime assets from the builder stage
COPY --from=builder /app/.build/debug /app
COPY --from=builder /app/Public /app/Public

EXPOSE 8080

RUN curl -fsSL https://releases.hashicorp.com/vault/1.16.2/vault_1.16.2_linux_amd64.zip -o vault.zip && \
    apt-get update && apt-get install -y unzip && \
    unzip vault.zip && mv vault /usr/local/bin/ && rm vault.zip

# Run Vault Agent and app together
CMD ["/bin/sh", "-c", "vault agent -config=/vault/vault-agent.hcl & while [ ! -f /vault/token.env ]; do sleep 0.1; done; . /vault/token.env && exec /app/mechasqueak"]
