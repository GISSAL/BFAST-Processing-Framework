# BFAST Processing Framework

A reproducible workstation-to-HPC workflow for large-scale BFAST analysis, breakpoint detection, and geospatial product generation from remote sensing time-series data.

This repository contains Python, R, and SLURM scripts used to preprocess geospatial time-series data, execute BFAST (Breaks For Additive Season and Trend) analyses on a high-performance computing cluster, and convert the results into GIS-ready vector, raster, and mosaic products.

The workflow was developed for large remote sensing datasets where observations are extracted at centroid locations, processed as tile-based time series, analyzed in parallel using BFAST, and reconstructed into spatial products for mapping and interpretation.

---

## Table of Contents

- [Overview](#overview)
- [Workflow Summary](#workflow-summary)
- [Repository Structure](#repository-structure)
- [Quick Start](#quick-start)
- [Software Requirements](#software-requirements)
- [Phase 1: Preprocessing](#phase-1-preprocessing)
- [Phase 2: HPC Processing](#phase-2-hpc-processing)
- [Phase 3: Post-Processing](#phase-3-post-processing)
- [Reproducibility Features](#reproducibility-features)
- [HPC Compatibility](#hpc-compatibility)
- [Documentation](#documentation)
- [Citation](#citation)
- [License Recommendation](#license-recommendation)

---

## Overview

BFAST is commonly used to detect structural changes in seasonal and trend components of time-series data. This repository provides a practical, end-to-end implementation for large geospatial datasets by dividing the workflow into manageable spatial tiles and using HPC resources for the computationally intensive BFAST stage.

The repository is organized around three phases:

1. **Preprocessing on a workstation**  
   Create tile shapefiles, extract raster values, fill missing observations, and generate quality assurance logs.

2. **Parallel BFAST processing on an HPC cluster**  
   Submit tile-level CSV files to SLURM, run optimized BFAST processing, and produce per-tile output files.

3. **Post-processing on a workstation**  
   Reconstruct BFAST outputs, join results back to spatial features, verify processing completion, create raster products, and build seamless mosaics.

---

## Workflow Summary

```text
Raw raster time series + centroid points + fishnet grid
        ↓
Phase 1: Preprocessing
        ├── Create tile shapefiles
        ├── Extract raster values at centroid locations
        ├── Fill missing observations
        └── Write QA logs and BFAST-ready tile CSVs
        ↓
Phase 2: HPC Processing
        ├── Submit tile CSV files to SLURM
        ├── Run optimized parallel BFAST
        └── Write trend, seasonal, residual, confidence interval, and NOBS outputs
        ↓
Phase 3: Post-Processing
        ├── Reconstruct and join BFAST outputs to spatial features
        ├── Verify completion across all tiles
        ├── Create progress maps
        ├── Convert joined results to raster tiles
        └── Build seamless regional mosaics
        ↓
Final tabular, vector, raster, mosaic, and QA products
```

---

## Repository Structure

A recommended structure is shown below. The scripts can be reorganized to match this layout before committing to GitHub.

```text
BFAST-Processing-Framework/
├── README.md
├── LICENSE
├── CITATION.cff
├── preprocessing/
│   ├── PythonScript_CreateTileShapefiles.py
│   ├── RScript_ExtractAndFill_Folder_with_QA.r
│   └── RScript_Cleanup_Extract_and_Results.r
├── hpc/
│   ├── BFAST_README.txt
│   ├── bfastParallel_optimized_chunked.R
│   ├── bfastParallel_optimized.R
│   ├── bfastParallel.sh
│   ├── superSubmit.sh
│   └── singleSubmit.sh
├── postprocessing/
│   ├── RScript_BFASTResults_And_Join_Folder.R
│   ├── RScript_Build_MasterProcessingLog.R
│   ├── RScript_BFASTProgressMap.r
│   ├── PythonScript_CreateResultRasters.py
│   └── PythonScript_MosaicResultRasters.py
└── docs/
    └── BFAST_User_Guide.md
```

---

## Quick Start

### 1. Prepare workstation inputs

Edit the paths and settings in:

```text
preprocessing/PythonScript_CreateTileShapefiles.py
preprocessing/RScript_ExtractAndFill_Folder_with_QA.r
```

Run the tile-creation and extraction workflows to produce filled tile CSV files such as:

```text
Centroids_80_fill.csv
Centroids_81_fill.csv
Centroids_82_fill.csv
```

### 2. Transfer filled CSV files to the HPC environment

Place filled CSV files in the HPC `Extract/` directory.

```text
~/Extract/
├── Centroids_80_fill.csv
├── Centroids_81_fill.csv
└── Centroids_82_fill.csv
```

### 3. Submit BFAST jobs

Submit all available tiles:

```bash
bash superSubmit.sh
```

Submit a tile range:

```bash
bash superSubmit.sh 80 120
```

Submit a single tile:

```bash
bash singleSubmit.sh Centroids_80_fill.csv
```

### 4. Download HPC outputs

After processing, transfer the BFAST output text files back to the workstation.

### 5. Reconstruct, join, and map results

Run the post-processing scripts in this order:

```text
RScript_BFASTResults_And_Join_Folder.R
RScript_Build_MasterProcessingLog.R
RScript_BFASTProgressMap.r
PythonScript_CreateResultRasters.py
PythonScript_MosaicResultRasters.py
```

---

## Software Requirements

### Python

- Python 3.x
- ArcPy
- ArcGIS Pro or a compatible ArcGIS Python environment
- ArcGIS Spatial Analyst extension for raster generation and mosaicking

### R

The scripts use several R packages, including:

```r
bfast
parallel
data.table
raster
sf
zoo
tools
broom
dplyr
stringr
readr
```

### HPC

- Linux-based HPC environment
- SLURM workload manager
- R installed on compute nodes
- Required R packages available in the HPC R environment

---

## Phase 1: Preprocessing

Phase 1 prepares data on a local workstation. It creates tile-specific point shapefiles, extracts raster time-series values at centroid locations, fills missing observations, and writes QA logs.

Primary scripts:

```text
PythonScript_CreateTileShapefiles.py
RScript_ExtractAndFill_Folder_with_QA.r
RScript_Cleanup_Extract_and_Results.r
```

---

## Phase 2: HPC Processing

Phase 2 runs BFAST on filled tile CSV files using SLURM job submission scripts and optimized R processing engines.

Primary scripts:

```text
bfastParallel_optimized_chunked.R
superSubmit.sh
singleSubmit.sh
```

The chunked BFAST engine reduces scheduling overhead by assigning groups of rows to each scheduled parallel task. It writes trend, seasonal, residual, confidence interval, and observation-count outputs.

---

## Phase 3: Post-Processing

Phase 3 converts raw BFAST outputs into GIS-ready products. The recommended sequence is:

1. Reconstruct and join BFAST results.
2. Verify completion across all tiles.
3. Visualize processing status.
4. Generate tile-level raster products.
5. Build seamless regional mosaics.

Primary scripts:

```text
RScript_BFASTResults_And_Join_Folder.R
RScript_Build_MasterProcessingLog.R
RScript_BFASTProgressMap.r
PythonScript_CreateResultRasters.py
PythonScript_MosaicResultRasters.py
```

---

## Reproducibility Features

This workflow includes several features intended to support long-running, large-area analyses:

- Tile-based processing
- Restart-safe extraction
- Restart-safe HPC submission
- Output-existence checks before job submission
- Per-tile extraction logs
- Missing-value QA logs
- BFAST processing logs
- Join summary logs
- Master processing summaries
- Progress maps
- Per-field raster creation logs
- Per-field mosaic update logs

---

## HPC Compatibility

> **Note:** This workflow was developed and tested on **Beocat**, the High Performance Computing cluster at Kansas State University. While the BFAST processing scripts are portable to most Linux-based HPC environments, some submission scripts, scheduler directives, resource specifications, node constraints, file paths, and monitoring commands may require modification to match local cluster configurations and workload managers.

The Beocat-specific monitoring commands documented in the user guide may not exist on other systems.

---

## Documentation

See the full guide for detailed instructions, user settings, parameter descriptions, output descriptions, and workflow notes:

```text
docs/BFAST_User_Guide.md
```

---

## Citation

If you use this workflow in a publication, report, thesis, dissertation, or derivative software project, please cite this repository and the original BFAST methodology.

---

## License Recommendation

For the stated goals of promoting reuse while discouraging privatization of improvements, the recommended license is:

```text
GNU Affero General Public License v3.0 (AGPL-3.0)
```
