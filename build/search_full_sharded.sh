#!/bin/bash
# search_full_sharded.sh
# Interactive search session against the 4-shard Enamine index
# with NPASS and DrugBank annotation.
# Databases are loaded once; then queries loop until you type 'quit'.

set -e

# ── Auto-detect build directory ───────────────────────────────────────────────
BUILD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load user configuration ───────────────────────────────────────────────────
CONF="$BUILD/config.sh"
if [ ! -f "$CONF" ]; then
    echo "ERROR: $CONF not found."
    echo "  cp $BUILD/config.sh.example $BUILD/config.sh"
    echo "  Then edit config.sh and set your data paths."
    exit 1
fi
source "$CONF"

if [ -z "$IDIR" ]; then
    echo "ERROR: IDIR is not set. Edit config.sh."
    exit 1
fi
if [ -z "$NPASS_RAW" ] || [ ! -d "$NPASS_RAW" ]; then
    echo "ERROR: NPASS_RAW directory not found: '${NPASS_RAW}'. Edit config.sh."
    exit 1
fi

cd "$BUILD"

# ── Verify shard config exists ────────────────────────────────────────────────
CONFIG="$IDIR/enamine_sharded/shard_config.json"
if [ ! -f "$CONFIG" ]; then
    echo "ERROR: shard_config.json not found at $CONFIG"
    echo "Run build_full_sharded.sh first."
    exit 1
fi

# ── Resolve DrugBank binary path ──────────────────────────────────────────────
# Priority: DRUGBANK_BIN from config → $IDIR/drugbank/drugbank.bin → skip
if [ -z "$DRUGBANK_BIN" ]; then
    DRUGBANK_BIN="$IDIR/drugbank/drugbank.bin"
fi

# ── Search ────────────────────────────────────────────────────────────────────
#
#   --k 5000       Per-shard candidates. 4 shards × 5000 = 20,000 total
#                  before global merge and exact rerank.
#                  Reduce to --k 1000 for faster exploratory queries.
#
#   --top 50       Final hits written to output TSV. Does not affect speed.
#
#   --nprobe 64    IVF cells probed per shard (nlist=4096 → 1.6%).
#                  Increase to 128 for higher recall, ~2× slower per shard.
#
#   --jobs 1       Number of shards searched in parallel.
#                  RAM/job: ~0.8 GB FAISS + shared 1.1 GB offsets.
#                  --jobs 4 cuts wall-clock search time ~4× (needs ~4 GB total).
#
#   --out-mode both
#                  Writes per query:
#                    results.tsv          — combined wide table
#                    results_enamine.tsv  — Enamine columns only
#                    results_npass.tsv    — NPASS similarity hits
#                    results_drugbank.tsv — DrugBank similarity hits

./search_sharded_database \
    --config       "$CONFIG" \
    --npass-index  "$NPASS_RAW" \
    --drugbank-bin "$DRUGBANK_BIN" \
    --databases    enamine,npass,drugbank \
    --metric       tanimoto \
    --k            5000 \
    --top          50 \
    --nprobe       64 \
    --jobs         1 \
    --out-mode     both \
    --out          "$IDIR/enamine_sharded/results.tsv"
