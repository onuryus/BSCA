#!/bin/bash
# search_test_sharded.sh
# Runs a single test query against the small 4-shard test index.
# Build the test index first with build_test_sharded.sh.

set -e

BUILD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONF="$BUILD/config.sh"
if [ ! -f "$CONF" ]; then
    echo "ERROR: $CONF not found. Copy config.sh.example and fill in your paths."
    exit 1
fi
source "$CONF"

if [ -z "$IDIR" ]; then
    echo "ERROR: IDIR is not set. Edit config.sh."
    exit 1
fi

cd "$BUILD"

./search_sharded_database \
    --config    "$IDIR/test_sharded/shard_config.json" \
    --query     "c1ccc2c(c1)sc1ccccc12" \
    --databases enamine \
    --metric    tanimoto \
    --k         200 \
    --top       50 \
    --nprobe    32 \
    --jobs      1 \
    --out-mode  both \
    --out       "$IDIR/test_sharded/results_test.tsv" \
    --no-gpu
