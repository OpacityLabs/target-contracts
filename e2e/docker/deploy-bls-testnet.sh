#!/bin/bash

# Get to the docker directory
DOCKER_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DOCKER_DIR"

docker compose -f bls-testnet.docker-compose.yml --env-file ../envs/bls-testnet.env build --no-cache 
docker compose -f bls-testnet.docker-compose.yml --env-file ../envs/bls-testnet.env up