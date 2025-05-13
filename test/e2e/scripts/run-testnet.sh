#!/bin/bash

cd "$(dirname "$0")"

./deploy-bridge.sh
./update-shim.sh
./get-sp1-block.sh
./generate-proof.sh