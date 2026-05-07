# BSCA
Billion-Scale Chemical Annotation

BSCA is a GPU-accelerated billion-scale chemical similarity search and biological annotation platform built with RDKit, FAISS, and memory-mapped indexing. (It's based on our previous project, BSCS)

The system is designed for ultra-large molecular databases ranging from millions to tens of billions of compounds while supporting fast approximate nearest neighbor retrieval, exact chemical reranking, and biological enrichment through NPASS and DrugBank integration.

BSCA supports:

- Billion-scale molecular similarity search
- FAISS IVF-PQ compressed vector indexing
- Exact RDKit similarity reranking
- Memory-mapped O(1) molecular retrieval
- NPASS biological annotation integration
- DrugBank pharmacology integration
- Enamine REAL database screening with annotations
- Sharded distributed indexing architecture
- GPU-accelerated index building
- Interactive multi-query search sessions

---

## Key Features

- Handles datasets from 136M to 10B+ molecules
- GPU-accelerated FAISS IVFPQ indexing
- Morgan fingerprint chemical representation
- Approximate nearest neighbor (ANN) retrieval
- Exact Tanimoto / Dice / Tversky reranking
- Memory-efficient mmap-based retrieval
- Multi-shard scalable architecture
- NPASS natural product integration
- DrugBank pharmacology and target integration
- Interactive search session mode
- Binary serialized indexes for fast startup

---

## Architecture Overview

BSCA uses a multi-stage retrieval pipeline:

```text
Query SMILES
      ↓
RDKit canonicalization
      ↓
Morgan fingerprint generation
      ↓
FAISS IVF-PQ ANN search  (per shard, sequential or parallel)
      ↓
Global candidate merge + deduplication
      ↓
Exact RDKit similarity reranking
      ↓
NPASS / DrugBank annotation
      ↓
Final ranked results  →  TSV output
```

The system supports both:
- **Single-index** workflows (up to ~136M molecules on a single machine)
- **Multi-shard** billion-scale workflows with a coordinator that builds and searches N equal shards

A single global offset file enables O(1) retrieval of any molecule directly from the original CXSMILES file without loading the database into RAM. All shards share this one file — the original SMILES data is never duplicated on disk.

---

## Supported Databases

### Enamine REAL
- Ultra-large synthesizable compound library (136M–10B+ molecules)
- Physicochemical descriptors (MW, logP, HBA, HBD, TPSA, QED, RotBonds, FSP3)
- Drug-likeness and fragment flags
- InChIKey for cross-database matching

### NPASS
- ~200K natural product compounds
- Biological activities with target information
- Toxicity data
- Organism sources and species pairs
- Protein targets

### DrugBank
- ~20K approved, investigational, and experimental drugs
- Full pharmacology text (mechanism, indication, metabolism, toxicity)
- Protein targets, enzymes, transporters, carriers
- Classification, synonyms, drug groups

---

## Installation

### Requirements

- Linux x86-64
- GCC 15+
- CUDA-capable GPU (optional, but strongly recommended for index building)
- CMake ≥ 3.16
- Conda / Mamba

### 1. Create the Conda environment

```bash
mamba create -n chem_cpp -c conda-forge \
    cmake make gcc gxx \
    boost-cpp eigen \
    faiss-gpu \
    -y

conda activate chem_cpp
```

### 2. Build and install RDKit

```bash
git clone https://github.com/rdkit/rdkit.git
cd rdkit && mkdir build && cd build

cmake \
    -DRDK_BUILD_PYTHON_WRAPPERS=OFF \
    -DRDK_INSTALL_INTREE=OFF \
    -DRDK_BUILD_FREETYPE_SUPPORT=OFF \
    -DRDK_BUILD_CAIRO_SUPPORT=OFF \
    -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
    ..

make -j$(nproc) && make install
cd ../..
```

### 3. Clone and build BSCA

```bash
git clone https://github.com/onuryus/BSCA.git
cd BSCA/build

cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

This produces the following executables in `build/`:

| Executable | Purpose |
|---|---|
| `prepare_enamine` | Scan Enamine CXSMILES → byte-offset index |
| `prepare_npass` | Load NPASS TSV files → binary lookup index |
| `prepare_drugbank` | Parse DrugBank XML → binary index |
| `build_enamine_index` | Build one FAISS IVFPQ shard |
| `build_sharded_database` | Coordinator: build all shards automatically |
| `search_sharded_database` | Multi-shard search + NPASS/DrugBank annotation |

---

## Configuration

All data paths are stored in a single config file that you fill in once.

```bash
cp build/config.sh.example build/config.sh
nano build/config.sh
```

`config.sh` is listed in `.gitignore` and is never committed.

```bash
# Enamine REAL Database CXSMILES file
ENAMINE=/path/to/Enamine_REAL_DB.cxsmiles

# Raw NPASS download directory (contains NPASS3.0_activities.txt etc.)
NPASS_RAW=/path/to/npass

# Index output directory (will be created automatically)
IDIR=/path/to/index

# DrugBank XML export — optional, requires a DrugBank account
DRUGBANK_XML=/path/to/drugbank.xml

# Pre-built DrugBank binary — optional, skips re-indexing if already built
DRUGBANK_BIN=/path/to/drugbank.bin
```

---

## Building the Index

```bash
cd BSCA/build
bash build_full_sharded.sh
```

The script runs three steps:

**Step 1 — NPASS** (~30 s)
Loads raw NPASS TSV files and writes a binary lookup index to `$IDIR/npass/`.

**Step 2 — DrugBank** (~12 s, optional)
Parses the DrugBank XML and writes `$IDIR/drugbank/drugbank.bin` (~82 MB).
Skipped gracefully if the XML is not found.

**Step 3 — Enamine sharded FAISS index**
Builds 4 equal shards of ~34M molecules each.
Asks once whether to use GPU; the choice is propagated to all shard builds.

```
shard 001  [mol 0 → 34M]   ████████████████  8 min (GPU)
shard 002  [mol 34M → 68M] ████████████████  11 min
shard 003  [mol 68M → 102M]████████████████  11 min
shard 004  [mol 102M → 136M]███████████████  12 min
```

**Re-runnable:** any already-built shard (`faiss.index` exists) is skipped.
Safe to interrupt at any point and re-run.

**Output structure:**

```
$IDIR/enamine_sharded/
├── shard_config.json        ← single metadata file (entry point for search)
├── enamine.offsets.bin      ← global byte-offset index (~1.1 GB)
├── enamine.header.tsv
├── enamine.count
├── shard_001/
│   └── faiss.index          ← IVFPQ index for molecules [0, 34M)
├── shard_002/
│   └── faiss.index
├── shard_003/
│   └── faiss.index
└── shard_004/
    └── faiss.index

$IDIR/npass/                 ← NPASS binary index (~200 MB)
$IDIR/drugbank/
└── drugbank.bin             ← DrugBank binary index (~82 MB)
```

---

## Searching

### Interactive session (recommended)

```bash
bash build/search_full_sharded.sh
```

Databases are loaded once. You enter a SMILES string, results are written to TSV files, and the session continues until you type `quit`.

```
Enter query SMILES (or 'quit'): c1ccc2c(c1)sc1ccccc12
  [Phase 2] NPASS similarity search → 3 hits (best: 0.847)
  [Phase 3] DrugBank similarity search → 1 hit (best: 0.762)
  [Phase 4] Shard 1/4: FAISS search ...
  ...
  [OK] 50 results written to results.tsv
Enter query SMILES (or 'quit'):
```

### Single query (non-interactive)

```bash
./build/search_sharded_database \
    --config       "$IDIR/enamine_sharded/shard_config.json" \
    --npass-index  "$NPASS_RAW" \
    --drugbank-bin "$IDIR/drugbank/drugbank.bin" \
    --query        "c1ccc2c(c1)sc1ccccc12" \
    --databases    enamine,npass,drugbank \
    --metric       tanimoto \
    --k            5000 \
    --top          50 \
    --nprobe       64 \
    --jobs         1 \
    --out-mode     both \
    --out          results.tsv
```

---

## Search Parameters

| Flag | Default | Description |
|---|---|---|
| `--metric` | `tanimoto` | Reranking metric: `tanimoto`, `dice`, `tversky`, `cosine`, `kulczynski` |
| `--k` | `5000` | Per-shard FAISS candidates (total candidates = k × num_shards before rerank) |
| `--nprobe` | `64` | IVF cells probed per shard — higher = better recall, slower |
| `--top` | `50` | Final hits written to output (does not affect speed) |
| `--jobs` | `1` | Shards searched in parallel (~0.8 GB RAM each) |
| `--databases` | — | Comma-separated: `enamine`, `nprobe`, `drugbank`, or `all` |
| `--out-mode` | — | `combined` \| `per-db` \| `both` |

---

## Output Format

With `--out-mode both` and `--out results.tsv`, four files are written per query:

| File | Contents |
|---|---|
| `results.tsv` | Combined wide table — all hits, all database columns |
| `results_enamine.tsv` | Enamine hits with all 19 Enamine descriptor columns |
| `results_npass.tsv` | NPASS-matched hits with activity, target, toxicity data |
| `results_drugbank.tsv` | DrugBank-matched hits with pharmacology columns |

Multi-query sessions auto-number output: `results.tsv`, `results_q002.tsv`, `results_q003.tsv`, …

---

## Performance

Benchmarked on **Enamine REAL 136M molecules**, 4 shards × 34M, RTX 4060 Laptop GPU (build), CPU (search):

### Build

| Step | Time |
|---|---|
| `prepare_enamine` (136M molecules, 23 GB file) | 27 s |
| Per-shard FAISS index — GPU (RTX 4060) | ~10–22 min |
| Full 4-shard build — GPU | ~1 h |
| Per-shard FAISS index — CPU (12 threads) | ~2–3 h |
| Full 4-shard build — CPU | ~8–12 h |

### Search — 136M molecules (4 shards, CPU vs GPU)

| Stage | CPU | GPU |
|---|---|---|
| NPASS + DrugBank load (first query only) | ~4 s | ~4 s |
| Per-shard FAISS search (nprobe=64, k=5000) | ~50–200 ms/shard | ~5–30 ms/shard |
| Enamine record retrieval (mmap, 20K reads) | ~100–300 ms | ~100–300 ms |
| Exact Tanimoto rerank (20K candidates) | ~200–500 ms | ~200–500 ms |
| Annotation + TSV write | ~5 ms | ~5 ms |
| **Total per query** | **~0.5–1.5 s** | **~0.3–1.0 s** |

### Search — large scale (GPU, per query)

| Database | Shards | Passes | FAISS search | Total |
|---|---|---|---|---|
| 1B mol (8 shards) | 8 | 1 | ~40–240 ms | **~0.4–1.0 s** |
| 10B mol (74 shards) | 74 | 3 | ~0.6–1.5 s | **~1–2.5 s** |

> Passes = number of search rounds based on available RAM (64 GB assumed).
> Retrieval and rerank cost scales with total candidates, not shard count.

---

## Scaling

| Molecules | Shards | Tier | Index Size | RAM (jobs=1) | Search |
|---|---|---|---|---|---|
| 136M | 4 | Balanced (m=16) | ~3.2 GB | ~2.5 GB | ~1 s |
| 1B | 8 | Balanced (m=16) | ~24 GB | ~4.6 GB | ~1 s |
| 6B | 44 | Balanced (m=16) | ~140 GB | ~4.6 GB | ~4 s |
| 10B | 74 | Compact (m=8) | ~160 GB | ~2.7 GB | ~3 s |

See `SCALE_GUIDE.txt` for full parameter recommendations.

---

## Index Parameters

| Parameter | Default | Description |
|---|---|---|
| `--nbits` | `1024` | Morgan FP bit count — higher = better chemistry, more RAM |
| `--nlist` | `4096` | IVF cell count — rule: `sqrt(N_shard)` to `4×sqrt(N_shard)` |
| `--m` | `16` | PQ sub-vectors — `m` bytes stored per molecule |
| `--train-size` | `500000` | Training molecules per shard (≥30×nlist recommended) |
| `--batch` | `1000000` | Add-batch size — controls build RAM: `batch × nbits × 4 bytes` |
| `--threads` | `12` | OMP threads for fingerprint computation |
| `--num-shards` | `4` | Number of equal shards |

---

## Data Sources

| Database | Access |
|---|---|
| **Enamine REAL** | [enamine.net](https://enamine.net/compound-collections/real-compounds/real-database) |
| **NPASS** | [bidd.group/NPASS](https://bidd.group/NPASS/) — free download |
| **DrugBank** | [go.drugbank.com](https://go.drugbank.com/releases/latest) — free academic account |
