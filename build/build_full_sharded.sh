#!/bin/bash
# build_full_sharded.sh
# Indexes NPASS, DrugBank, and Enamine (4 shards × ~34M) from scratch.
# Run once. Takes ~35 min on GPU, several hours on CPU.
# Safe to interrupt and re-run — already-built shards are skipped automatically.

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

# ── Validate required paths ───────────────────────────────────────────────────
if [ -z "$ENAMINE" ] || [ ! -f "$ENAMINE" ]; then
    echo "ERROR: ENAMINE file not found: '${ENAMINE}'"
    echo "  Edit config.sh and set ENAMINE to your Enamine CXSMILES file."
    exit 1
fi
if [ -z "$NPASS_RAW" ] || [ ! -d "$NPASS_RAW" ]; then
    echo "ERROR: NPASS_RAW directory not found: '${NPASS_RAW}'"
    echo "  Edit config.sh and set NPASS_RAW to your NPASS download directory."
    exit 1
fi
if [ -z "$IDIR" ]; then
    echo "ERROR: IDIR is not set."
    echo "  Edit config.sh and set IDIR to your desired index output directory."
    exit 1
fi

cd "$BUILD"

echo ""
echo "================================================================="
echo "  BSCS Full Sharded Build"
echo "  Enamine : $ENAMINE"
echo "  NPASS   : $NPASS_RAW"
echo "  Output  : $IDIR"
echo "================================================================="
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: Index NPASS
#   Reads raw NPASS TSV files and writes a fast binary lookup index.
#   Input : raw NPASS download directory (contains NPASS3.0_activities.txt etc.)
#   Output: $IDIR/npass/  (binary files used at query time)
# ─────────────────────────────────────────────────────────────────────────────
echo "[STEP 1] Indexing NPASS..."
mkdir -p "$IDIR/npass"

if [ "$(ls -A "$IDIR/npass" 2>/dev/null)" ]; then
    echo "  NPASS index already exists at $IDIR/npass — skipping."
    echo "  (Delete $IDIR/npass and re-run to rebuild.)"
else
    ./prepare_npass \
        --npass-dir "$NPASS_RAW" \
        --outdir    "$IDIR/npass"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: Index DrugBank (optional — requires a DrugBank account and licence)
#   Input : drugbank.xml  (~2.4 GB XML)
#   Output: $IDIR/drugbank/drugbank.bin  (fast binary, ~82 MB)
# ─────────────────────────────────────────────────────────────────────────────
echo "[STEP 2] Indexing DrugBank..."
mkdir -p "$IDIR/drugbank"

if [ -n "$DRUGBANK_BIN" ] && [ -f "$DRUGBANK_BIN" ]; then
    echo "  Pre-built DrugBank binary found at $DRUGBANK_BIN — skipping."
elif [ -f "$IDIR/drugbank/drugbank.bin" ]; then
    echo "  DrugBank binary already exists at $IDIR/drugbank/drugbank.bin — skipping."
    DRUGBANK_BIN="$IDIR/drugbank/drugbank.bin"
elif [ -n "$DRUGBANK_XML" ] && [ -f "$DRUGBANK_XML" ]; then
    ./prepare_drugbank \
        --xml    "$DRUGBANK_XML" \
        --outdir "$IDIR/drugbank"
    DRUGBANK_BIN="$IDIR/drugbank/drugbank.bin"
else
    echo "  DrugBank XML not found (DRUGBANK_XML='${DRUGBANK_XML}')."
    echo "  Skipping DrugBank. Set DRUGBANK_XML in config.sh to enable it."
    DRUGBANK_BIN=""
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3: Build sharded Enamine FAISS index (4 shards × ~34M molecules)
#
#   Parameters for ~34M molecules per shard (Balanced tier):
#     --nlist 4096      IVF cells. Rule: sqrt(34M)≈5831; 4096 is within range.
#     --m 16            PQ sub-vectors. 16 bytes/mol. "Balanced" quality.
#     --nbits 1024      Fingerprint bits. Standard.
#     --train-size 500000  Molecules to train the FAISS quantizer.
#                          Rule: ≥30×nlist = 122,880. 500K is safe.
#     --batch 1000000   Molecules per add-batch.
#                         1M × 1024 dims × 4 bytes = 4 GB build RAM peak.
#                         Reduce to 500000 if OOM during build.
#     --threads 12      OMP threads for fingerprint compute.
#
#   Each shard takes ~10-22 min on GPU, ~2-3 h on CPU (12 threads).
#   Total: ~40-90 min GPU, ~8-12 h CPU for all 4 shards.
#   Already-built shards are skipped automatically on re-run.
# ─────────────────────────────────────────────────────────────────────────────
echo "[STEP 3] Building 4-shard Enamine FAISS index..."
echo "  Each shard is skipped if already built."
echo ""

./build_sharded_database \
    --input        "$ENAMINE" \
    --outdir       "$IDIR/enamine_sharded" \
    --num-shards   4 \
    --radius       3 \
    --nbits        1024 \
    --nlist        4096 \
    --m            16 \
    --nbits-pq     8 \
    --train-size   500000 \
    --batch        1000000 \
    --threads      12 \
    --yes

echo ""
echo "================================================================="
echo "  Build complete."
echo ""
echo "  Index location : $IDIR/enamine_sharded/"
echo "  NPASS index    : $IDIR/npass/"
if [ -n "$DRUGBANK_BIN" ]; then
echo "  DrugBank index : $DRUGBANK_BIN"
else
echo "  DrugBank index : (not built — set DRUGBANK_XML in config.sh)"
fi
echo ""
echo "  Run searches with:"
echo "    ./search_full_sharded.sh"
echo "================================================================="
