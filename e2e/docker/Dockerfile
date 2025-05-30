# Build stage for contracts
FROM ghcr.io/foundry-rs/foundry:stable AS builder

USER root

WORKDIR /app

# Copy contracts directory and install dependencies
COPY contracts/ contracts/
WORKDIR /app/contracts

# Install dependencies and build contracts
RUN forge build

# Final stage
FROM ghcr.io/foundry-rs/foundry:stable

USER root

WORKDIR /app

# Install required tools for the e2e scripts
RUN apt-get update && apt-get install -y \
    jq \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy built contracts and forge artifacts
COPY --from=builder /app/contracts/lib /app/contracts/lib
COPY --from=builder /app/contracts/out /app/contracts/out
COPY --from=builder /app/contracts/src /app/contracts/src
COPY --from=builder /app/contracts/script /app/contracts/script
COPY --from=builder /app/contracts/foundry.toml /app/contracts/foundry.toml

# Copy e2e test scripts and entrypoint
COPY e2e/docker/scripts /app/scripts

# Define volume for node data persistence
VOLUME ["/app/.nodes"]

# Define volume for artifacts persistence
VOLUME ["/app/artifacts"]

# Define volume for envs persistence
VOLUME ["/app/envs"]

ENTRYPOINT ["/app/scripts/run-testnet.sh"]
