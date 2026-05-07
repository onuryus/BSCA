cmake_minimum_required(VERSION 3.16)
project(bscs VERSION 2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ── compile flags ──────────────────────────────────────────────────────────────
add_compile_options(
    -O3
    -march=native
    -funroll-loops
    -ffast-math
    -Wall
    -Wextra
    -Wno-unused-parameter
)

# ── find packages ──────────────────────────────────────────────────────────────
find_package(OpenMP REQUIRED)

# RDKit and FAISS via conda prefix
set(CONDA_PREFIX $ENV{CONDA_PREFIX})
if(NOT CONDA_PREFIX)
    message(FATAL_ERROR "CONDA_PREFIX not set. Activate your conda environment.")
endif()

include_directories(
    ${CONDA_PREFIX}/include/rdkit
    ${CONDA_PREFIX}/include
)
link_directories(
    ${CONDA_PREFIX}/lib
)

# CUDA headers for faiss-gpu (cublas_v2.h etc.)
find_path(CUDA_INCLUDE_DIR cublas_v2.h
    PATHS /usr/local/cuda/include /usr/local/cuda-12.5/include
    NO_DEFAULT_PATH)
if(CUDA_INCLUDE_DIR)
    include_directories(${CUDA_INCLUDE_DIR})
    message(STATUS "CUDA include: ${CUDA_INCLUDE_DIR}")
else()
    message(WARNING "CUDA headers not found; GPU index build may fail")
endif()

# ── shared RDKit + FAISS link list ─────────────────────────────────────────────
set(RDKIT_LIBS
    RDKitGraphMol
    RDKitSmilesParse
    RDKitRDGeneral
    RDKitFingerprints
    RDKitDataStructs
    RDKitMolStandardize
)

set(COMMON_LIBS
    faiss
    ${RDKIT_LIBS}
    OpenMP::OpenMP_CXX
)

# ── legacy tools (kept for compatibility) ─────────────────────────────────────
add_executable(build_index  src/build_index.cpp)
add_executable(search_index src/search_index.cpp)

target_link_libraries(build_index  ${COMMON_LIBS})
target_link_libraries(search_index ${COMMON_LIBS})

# ── new pipeline tools ────────────────────────────────────────────────────────

# 1. prepare_enamine: scans Enamine file, writes offset index
add_executable(prepare_enamine src/prepare_enamine.cpp)
target_link_libraries(prepare_enamine ${COMMON_LIBS})
target_include_directories(prepare_enamine PRIVATE src)

# 2. build_enamine_index: builds FAISS IVFPQ from Enamine + offset index
add_executable(build_enamine_index src/build_enamine_index.cpp)
target_link_libraries(build_enamine_index ${COMMON_LIBS})
target_include_directories(build_enamine_index PRIVATE src)

# 3. prepare_npass: loads NPASS tables, writes binary lookup index
add_executable(prepare_npass src/prepare_npass.cpp)
target_link_libraries(prepare_npass ${COMMON_LIBS})
target_include_directories(prepare_npass PRIVATE src)

# 4. search_annotate: full search + rerank + Enamine + NPASS + DrugBank annotation
add_executable(search_annotate src/search_annotate.cpp)
target_link_libraries(search_annotate ${COMMON_LIBS})
target_include_directories(search_annotate PRIVATE src)

# 5. prepare_drugbank: parses DrugBank XML, writes binary lookup index
add_executable(prepare_drugbank src/prepare_drugbank.cpp)
target_link_libraries(prepare_drugbank ${COMMON_LIBS})
target_include_directories(prepare_drugbank PRIVATE src)

# 6. build_sharded_database: splits Enamine into shards, builds all FAISS indices
add_executable(build_sharded_database src/build_sharded_database.cpp)
target_link_libraries(build_sharded_database ${COMMON_LIBS})
target_include_directories(build_sharded_database PRIVATE src)

# 7. search_sharded_database: multi-shard similarity search + annotation
add_executable(search_sharded_database src/search_sharded_database.cpp)
target_link_libraries(search_sharded_database ${COMMON_LIBS})
target_include_directories(search_sharded_database PRIVATE src)

# ── install to build dir ──────────────────────────────────────────────────────
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})
