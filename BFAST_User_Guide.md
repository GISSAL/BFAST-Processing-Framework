# BFAST Processing Framework User Guide

## Table of Contents

- Overview
- Workflow Overview
- Phase 1 – Preprocessing
- Phase 2 – HPC Processing
- Phase 3 – Post-Processing and Product Generation
- Reproducibility Features
- Final Outputs

---

# Overview

This guide describes the complete workflow used to prepare, process, analyze, and map large-scale remotely sensed time-series datasets using the BFAST framework.

## Workflow Overview

```text
Raw Spatial Data
        ↓
Create Tile Shapefiles
        ↓
Extract Raster Time Series
        ↓
Gap Fill Missing Values
        ↓
Tile CSV Files
        ↓
Parallel BFAST Processing
        ↓
BFAST Outputs
        ↓
Join Results
        ↓
Verify Completion
        ↓
Create Rasters
        ↓
Build Mosaics
        ↓
Final Products
```

# Phase 1 — Preprocessing

For each script include:
- Purpose
- Inputs
- User Settings
- Process
- Outputs
- Recommendations

Scripts:
- PythonScript_CreateTileShapefiles.py
- RScript_ExtractAndFill_Folder_with_QA.r
- RScript_Cleanup_Extract_and_Results.r

# Phase 2 — High Performance Computing (HPC) Processing

> Note: This workflow was developed and tested on Beocat at Kansas State University. Submission scripts and monitoring commands may require modification for other HPC environments.

Scripts:
- bfastParallel_optimized.R
- bfastParallel_optimized_chunked.R
- superSubmit.sh
- singleSubmit.sh

For each script document:
- Purpose
- User Settings
- Recommended Values
- Outputs
- Example Usage

# Phase 3 — Post-Processing and Product Generation

## Step 1: Reconstruct and Join BFAST Results
- RScript_BFASTResults_And_Join_Folder.R

## Step 2: Verify Processing Completion
- RScript_Build_MasterProcessingLog.R

## Step 3: Visualize Processing Status
- RScript_BFASTProgressMap.r

## Step 4: Create Tile-Level Raster Products
- PythonScript_CreateResultRasters.py

## Step 5: Build Regional Mosaics
- PythonScript_MosaicResultRasters.py

For each script document:
- Purpose
- User Settings
- Outputs
- Recommendations

# Reproducibility Features

- Restart-safe processing
- Quality assurance logging
- Incremental raster generation
- Incremental mosaic updates
- Master processing logs

# Final Outputs

- Tabular outputs
- Spatial outputs
- Quality assurance outputs
