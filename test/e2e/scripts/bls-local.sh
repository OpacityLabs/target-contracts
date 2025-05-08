#!/bin/bash

# Get to the docker directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"/../docker

docker compose -f bls-local.docker-compose.yml --env-file ../envs/bls-local.env build --no-cache 
docker compose -f bls-local.docker-compose.yml --env-file ../envs/bls-local.env up 