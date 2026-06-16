# BFAST Processing Framework

A reproducible workstation-to-HPC workflow for large-scale BFAST analysis, breakpoint detection, QA/QC, ecological classification, raster generation, and mosaic creation from remote sensing time-series data.

This repository contains Python, R, and SLURM scripts used to preprocess geospatial time-series data, execute BFAST (Breaks For Additive Season and Trend) analyses on a high-performance computing cluster, and convert the results into GIS-ready vector, raster, mosaic, and quality-assurance products.

The current QA-enabled workflow supports an 11-class grassland change interpretation framework, pixel-level interpolation QA, ID-based join validation, trend-warning tracking, pixel accounting, and restart-safe processing across workstation and HPC stages.

---

## Workflow Summary

```text
Raw raster time series + centroid points + fishnet grid
        ↓
Phase 1: Workstation preprocessing
        ├── Create tile shapefiles
        ├── Extract raster values at centroid locations
        ├── Fill missing observations
        └── Write extraction and interpolation QA logs
        ↓
Phase 2: HPC BFAST processing
        ├── Submit filled tile CSV files to SLURM
        ├── Run optimized parallel BFAST processing
        └── Write trend, seasonal, confidence interval, magnitude, fitted component, and NOBS outputs
        ↓
Phase 3: QA-enabled post-processing
        ├── Reconstruct per-tile BFAST result tables
        ├── Estimate trend slope and trend significance
        ├── Assign 11 ecological classes
        ├── Join results to centroid shapefiles by pointid/ID
        ├── Write mismatch, accounting, dropped-pixel, and processing logs
        ├── Convert joined results to raster tiles
        └── Build regional/statewide mosaics
        ↓
Final CSV, shapefile, raster, mosaic, and QA products
```

---

## Repository Structure

Scripts remain in the repository root.

```text
BFAST-Processing-Framework/
├── README.md
├── LICENSE
├── CITATION.cff
├── PythonScript_CreateTileShapefiles.py
├── PythonScript_CreateResultRasters_QA.py
├── PythonScript_MosaicResultRasters_QA.py
├── RScript_ExtractAndFill_Folder_with_QA.r
├── RScript_Cleanup_Extract_and_Results.r
├── RScript_BFASTResults_And_Join_Folder_QA.R
├── RScript_Build_MasterProcessingLog.R
├── RScript_BFASTProgressMap.r
├── bfastParallel_optimized_chunked.R
├── singleSubmit.sh
├── superSubmit.sh
└── docs/
    ├── BFAST_User_Guide.md
    ├── BFAST_Grassland_Classification_Workflow_Manual_v3.docx
    └── BFAST_Classification_Technical_Manual_v3.docx
```

---

## Quick Start

### 1. Create tile shapefiles

Edit paths in:

```text
PythonScript_CreateTileShapefiles.py
```

Run the script in an ArcGIS Pro Python environment to create tile shapefiles named:

```text
Centroids_<TileID>.shp
```

Each tile shapefile must contain a unique `pointid` field.

### 2. Extract and fill raster time series

Edit paths in:

```text
RScript_ExtractAndFill_Folder_with_QA.r
```

Run the script to produce raw and filled CSV files, plus extraction and interpolation QA logs:

```text
Centroids_<TileID>.csv
Centroids_<TileID>_fill.csv
extract_log.csv
na_fill_log.csv
na_fill_pixel_qa_log.csv
na_fill_summary_qa_log.csv
```

### 3. Run BFAST on the HPC system

Transfer filled CSV files to the HPC input directory, then submit jobs using the SLURM scripts.

Submit all available tiles:

```bash
bash superSubmit.sh
```

Submit a tile range:

```bash
bash superSubmit.sh 80 120
```

Submit one tile:

```bash
bash singleSubmit.sh Centroids_80_fill.csv
```

### 4. Reconstruct, classify, and join BFAST outputs

After downloading HPC outputs, edit paths in:

```text
RScript_BFASTResults_And_Join_Folder_QA.R
```

Run the script to reconstruct BFAST outputs, assign ecological classes, join results to centroid shapefiles, and write QA/accounting logs.

### 5. Create raster tiles and mosaics

Edit paths in:

```text
PythonScript_CreateResultRasters_QA.py
PythonScript_MosaicResultRasters_QA.py
```

Run the raster script first, then the mosaic script.

---

## Main Scripts

| Script | Stage | Purpose |
|---|---:|---|
| `PythonScript_CreateTileShapefiles.py` | 1 | Splits centroid points into tile shapefiles using a fishnet grid. |
| `RScript_ExtractAndFill_Folder_with_QA.r` | 1 | Extracts raster time series, fills missing values, and writes pixel/tile QA logs. |
| `RScript_Cleanup_Extract_and_Results.r` | 1/3 | Deletes selected intermediate files after verification. |
| `bfastParallel_optimized_chunked.R` | 2 | Runs optimized parallel BFAST processing on filled tile CSV files. |
| `superSubmit.sh` | 2 | Submits multiple tile jobs to SLURM, with restart-safe output checks. |
| `singleSubmit.sh` | 2 | Submits one tile job to SLURM, with output checks. |
| `RScript_BFASTResults_And_Join_Folder_QA.R` | 3 | Reconstructs BFAST outputs, assigns 11 ecological classes, joins to shapefiles, and writes QA/accounting logs. |
| `RScript_Build_MasterProcessingLog.R` | 3 | Combines processing-stage logs into a master progress summary. |
| `RScript_BFASTProgressMap.r` | 3 | Joins progress summaries to the fishnet grid for mapping. |
| `PythonScript_CreateResultRasters_QA.py` | 3 | Converts joined result shapefiles to QA-aware raster tiles. |
| `PythonScript_MosaicResultRasters_QA.py` | 3 | Mosaics tile rasters and labels categorical outputs. |

---

## Ecological Classification Framework

The QA-enabled post-processing script assigns the following class codes:

| Code | Label |
|---:|---|
| 1 | Stable grassland |
| 2 | Climate-driven variability |
| 3 | Abrupt decline |
| 4 | Recovery trajectory |
| 5 | Sustained degradation |
| 6 | Sustained improvement |
| 7 | Phenological shift |
| 8 | Highly dynamic |
| 9 | Gradual decline |
| 10 | Gradual improvement |
| 11 | Other |
| -9999 | Missing/NoData |

Trend direction is also encoded numerically:

| TREND | `trend_direction_code` |
|---|---:|
| Negative | -1 |
| Stable | 0 |
| Positive | 1 |
| Missing/NoData | -9999 |

The classification is threshold-based and order-dependent. See `docs/BFAST_Classification_Technical_Manual_v3.docx` for the full decision tree, thresholds, QA logic, and interpretation cautions.

---

## QA/QC Features

The current workflow includes:

- pixel-level missing-value and interpolation QA;
- moderate, excessive, and severe interpolation flags;
- trend regression warning retention;
- ID-based joins rather than row-order joins;
- duplicate ID and duplicate pointid checks;
- shapefile/result mismatch reporting;
- pixel accounting across processing stages;
- dropped-pixel reason logging;
- raster and mosaic processed logs for restart-safe updates.

Important QA outputs include:

```text
extract_log.csv
na_fill_log.csv
na_fill_pixel_qa_log.csv
na_fill_summary_qa_log.csv
bfast_results_log.csv
bfast_trend_cumulative.csv
join_results_log.csv
pixel_accounting_log.csv
dropped_pixel_reason_log.csv
CreateResultRasters_INTERP_QA_run_summary.csv
MosaicResultRasters_INTERP_QA_run_summary.csv
```

---

## Software Requirements

### Python / ArcGIS

- Python 3.x in an ArcGIS-compatible environment
- ArcPy
- ArcGIS Pro
- Spatial Analyst extension for raster products

### R

Required packages used across the R workflow include:

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

The HPC scripts assume:

- Linux shell environment
- SLURM workload manager
- R installed on compute nodes
- required R packages available on compute nodes

The workflow was developed and tested on Beocat at Kansas State University. Other clusters may require changes to scheduler directives, resource settings, paths, modules, and monitoring commands.

---

## Documentation

Detailed documentation is provided in:

```text
docs/BFAST_User_Guide.md
docs/BFAST_Grassland_Classification_Workflow_Manual_v3.docx
docs/BFAST_Classification_Technical_Manual_v3.docx
```

Use the User Guide for operational instructions. Use the Workflow Manual for the full processing workflow and QA review checklist. Use the Technical Manual for classification logic, thresholds, output fields, and interpretation guidance.

---

## Version Notes

The v3 QA-enabled documentation and scripts supersede earlier drafts that described an 8-class interpretation framework. The current workflow uses 11 classes, retains trend warnings as QA metadata, supports optional interpolation QA, joins by ID, writes mismatch files, and creates both tile-level and per-pixel QA/accounting logs.

---

## Citation

If you use this workflow in a publication, report, thesis, dissertation, or derivative software project, please cite this repository and the original BFAST methodology.

GitHub citation metadata is provided in:

```text
CITATION.cff
```

---

## License

This repository is distributed under the GNU General Public License v3.0. See:

```text
LICENSE
```
