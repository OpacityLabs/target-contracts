#!/bin/bash
# search_state_root.sh
#
# Usage: ./search_state_root.sh <target_state_root> <start_block> <end_block>
# Example: ./search_state_root.sh 0xabcdef1234567890... 1000000 1000100
#
# This script iterates over block numbers from <start_block> to <end_block> and
# prints the block number and hex value of any block whose execution state root 
# matches the given target state root.

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <target_state_root> <start_block> <end_block>"
  exit 1
fi

TARGET_STATE_ROOT=$1
START_BLOCK=$2
END_BLOCK=$3
RPC_URL="https://ethereum-holesky-rpc.publicnode.com"  # Change this URL to your Ethereum node RPC endpoint if needed

echo "Searching for blocks with state root: $TARGET_STATE_ROOT between blocks $START_BLOCK and $END_BLOCK"

for (( block = START_BLOCK; block <= END_BLOCK; block++ ))
do
  # Format block number in hex (Ethereum expects 0x prefixed hex block numbers)
  block_hex=$(printf "0x%x" $block)
  
  # Fetch the block header using eth_getBlockByNumber (without transactions)
  response=$(curl -s --data '{
    "jsonrpc": "2.0",
    "method": "eth_getBlockByNumber",
    "params": ["'$block_hex'", false],
    "id": 1
  }' -H "Content-Type: application/json" $RPC_URL)
  
  # Extract the stateRoot field using jq
  state_root=$(echo "$response" | jq -r '.result.stateRoot')
  
  # Check if the state root matches the target
  if [ "$state_root" == "$TARGET_STATE_ROOT" ]; then
    block_hash=$(echo "$response" | jq -r '.result.hash')
    echo "Match found: Block $block ($block_hex)"
    echo "  Block hash: $block_hash"
    echo "  State Root: $state_root"
  fi
done

echo "Search complete."