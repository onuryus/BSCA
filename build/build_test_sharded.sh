#!/bin/bash
# build_test_sharded.sh
# Builds a small 4-shard test index from a 100K-molecule sample.
# Used to verify the sharded pipeline without waiting hours.
# Run prepare_enamine on a 100K sample first (see ARCHITECTURE.txt).

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

./build_sharded_database \
    --input      "$IDIR/test_sample/sample_100k.cxsmiles" \
    --outdir     "$IDIR/test_sharded" \
    --num-shards 4 \
    --no-gpu \
    --radius     3 \
    --nbits      1024 \
    --nlist      512 \
    --m          8 \
    --nbits-pq   8 \
    --train-size 5000 \
    --batch      50000 \
    --threads    8 \
    --yes
