# BFAST Processing Framework

A scalable workflow for preprocessing, parallel BFAST analysis, and post-processing of remotely sensed vegetation time-series data.

## Overview

The workflow is organized into three phases:

### Phase 1 — Preprocessing (Workstation)
- Create tile shapefiles
- Extract raster time-series values
- Fill missing observations
- Perform quality assurance checks
- Prepare tile-specific input files

### Phase 2 — HPC Processing
- Submit jobs to an HPC cluster
- Run optimized BFAST workflows
- Generate trend and seasonal break metrics
- Produce confidence intervals and diagnostics

### Phase 3 — Post-Processing (Workstation)
- Reconstruct spatial outputs
- Verify processing completion
- Generate raster products
- Create regional mosaics
- Produce final maps and summaries

## Workflow Overview

```text
Raw Spatial Data
        ↓
Phase 1: Preprocessing
        ↓
Tile CSV Files
        ↓
Phase 2: HPC Processing
        ↓
BFAST Output Files
        ↓
Phase 3: Post-Processing
        ↓
Final Spatial Products
```

## Repository Structure

```text
preprocessing/
hpc/
postprocessing/
docs/
└── BFAST_User_Guide.md
```

## HPC Compatibility

This workflow was developed and tested on Beocat at Kansas State University. Some scheduler directives and monitoring commands may require modification for other HPC environments.

## Getting Started

1. Complete Phase 1 preprocessing.
2. Transfer tile CSV files to your HPC environment.
3. Execute BFAST processing.
4. Download outputs.
5. Run post-processing workflows.
6. Generate final raster and mosaic products.

See `docs/BFAST_User_Guide.md` for complete documentation.
