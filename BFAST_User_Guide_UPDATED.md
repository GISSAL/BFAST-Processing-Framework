# BFAST Processing Framework User Guide

A comprehensive operational guide for preprocessing, HPC-based BFAST analysis, QA-enabled post-processing, ecological classification, raster generation, and mosaicking of large remote sensing time-series datasets.

This guide assumes that scripts are stored in the repository root.

---

## Table of Contents

- [1. Purpose and Scope](#1-purpose-and-scope)
- [2. Workflow Overview](#2-workflow-overview)
- [3. Repository Layout](#3-repository-layout)
- [4. Software Requirements](#4-software-requirements)
- [5. Phase 1: Workstation Preprocessing](#5-phase-1-workstation-preprocessing)
  - [5.1 Create Tile Shapefiles](#51-create-tile-shapefiles)
  - [5.2 Extract Raster Time Series and Fill Missing Values](#52-extract-raster-time-series-and-fill-missing-values)
  - [5.3 Cleanup and Storage Management](#53-cleanup-and-storage-management)
- [6. Phase 2: HPC BFAST Processing](#6-phase-2-hpc-bfast-processing)
  - [6.1 HPC Environment Note](#61-hpc-environment-note)
  - [6.2 Expected HPC Directory Structure](#62-expected-hpc-directory-structure)
  - [6.3 BFAST Input Format](#63-bfast-input-format)
  - [6.4 Optimized Chunked BFAST Processing](#64-optimized-chunked-bfast-processing)
  - [6.5 Batch Job Submission](#65-batch-job-submission)
  - [6.6 Single-Tile Job Submission](#66-single-tile-job-submission)
  - [6.7 BFAST Output Products](#67-bfast-output-products)
  - [6.8 Monitoring and Management](#68-monitoring-and-management)
- [7. Phase 3: QA-Enabled Post-Processing and Product Generation](#7-phase-3-qa-enabled-post-processing-and-product-generation)
  - [7.1 Reconstruct, Classify, and Join BFAST Results](#71-reconstruct-classify-and-join-bfast-results)
  - [7.2 Verify Processing Completion](#72-verify-processing-completion)
  - [7.3 Visualize Processing Status](#73-visualize-processing-status)
  - [7.4 Create Tile-Level Raster Products](#74-create-tile-level-raster-products)
  - [7.5 Build Regional Mosaics](#75-build-regional-mosaics)
- [8. Classification and Output Field Reference](#8-classification-and-output-field-reference)
- [9. QA/QC Logs and Restart-Safe Design](#9-qaqc-logs-and-restart-safe-design)
- [10. Suggested Troubleshooting Checks](#10-suggested-troubleshooting-checks)
- [11. Documentation, Citation, and License](#11-documentation-citation-and-license)

---

## 1. Purpose and Scope

This guide documents a complete workflow for running large-scale BFAST analyses on remote sensing time-series data. The workflow extracts raster values at centroid or pixel locations, splits the analysis into spatial tiles, processes each tile on an HPC system, reconstructs BFAST outputs, assigns ecological classes, joins results back to spatial features, and produces QA-aware raster and mosaic products.

The current workflow is QA-enabled. In addition to final ecological classes, it records interpolation severity, trend warnings, join mismatches, dropped-pixel reasons, and cross-stage pixel accounting.

---

## 2. Workflow Overview

```text
Input spatial data
├── Raster time series
├── Centroid point feature class
└── Fishnet tile grid
        ↓
Phase 1: Workstation preprocessing
├── Create one centroid shapefile per tile
├── Extract raster values for each centroid
├── Fill missing values
└── Write BFAST-ready tile CSV files and QA logs
        ↓
Phase 2: HPC BFAST processing
├── Transfer filled CSV files to HPC Extract/
├── Submit SLURM jobs using singleSubmit.sh or superSubmit.sh
├── Run optimized BFAST processing in parallel
└── Write BFAST text outputs per tile
        ↓
Phase 3: QA-enabled post-processing
├── Reconstruct per-tile BFAST result tables
├── Estimate trend slope and p-value
├── Assign 11 ecological classes
├── Join results to tile shapefiles by pointid/ID
├── Write processing, mismatch, accounting, and dropped-pixel logs
├── Convert joined point results to raster tiles
└── Mosaic tile rasters into regional products
```

---

## 3. Repository Layout

Scripts are stored in the repository root.

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

## 4. Software Requirements

### Python and ArcGIS

The Python scripts use ArcPy and should be run in an ArcGIS-compatible Python environment.

Required:

- Python 3.x
- ArcPy
- ArcGIS Pro or equivalent ArcGIS Python environment
- ArcGIS Spatial Analyst extension for raster products

### R

Required packages used across the R scripts include:

| Package | Used For |
|---|---|
| `raster` | Raster stack creation and point extraction |
| `sf` | Vector data reading, writing, and spatial joins |
| `zoo` | Linear interpolation and forward/backward filling |
| `tools` | File and extension utilities |
| `bfast` | BFAST decomposition and breakpoint detection |
| `parallel` | Parallel execution on allocated cores |
| `data.table` | Fast tabular reading and writing |
| `broom` | Model output tidying |
| `dplyr` | Data manipulation |
| `stringr` | Tile-number parsing |
| `readr` | CSV reading for progress map creation |

### HPC

The submission scripts assume:

- Linux shell environment
- SLURM workload manager
- R available on compute nodes
- required R packages available on compute nodes

---

## 5. Phase 1: Workstation Preprocessing

Phase 1 prepares tile-level time-series inputs for the HPC environment.

---

## 5.1 Create Tile Shapefiles

### Script

```text
PythonScript_CreateTileShapefiles.py
```

### Purpose

This script partitions a large centroid dataset into tile-specific shapefiles using a fishnet grid. Each fishnet polygon is used to select intersecting centroid points, and the selected points are exported as a separate shapefile named by tile number.

### Inputs

- Point feature class containing centroid or pixel locations.
- Fishnet polygon feature class defining spatial processing tiles.
- Tile identifier field in the fishnet layer.
- Output folder for tile shapefiles.

### Outputs

```text
Centroids_<TileID>.shp
```

### Recommendations

- Ensure the point and fishnet layers use compatible coordinate systems.
- Confirm that the fishnet tile field contains unique tile identifiers.
- Confirm that each output shapefile includes a unique `pointid` field.
- Keep tile names consistent because later scripts expect names beginning with `Centroids_`.

---

## 5.2 Extract Raster Time Series and Fill Missing Values

### Script

```text
RScript_ExtractAndFill_Folder_with_QA.r
```

### Purpose

This script extracts a time series of raster values at each centroid location, writes raw extraction CSV files, fills missing values, writes filled CSV files, and creates tile-level and pixel-level QA logs.

The first output column is the shapefile field `pointid`. This field is preserved unchanged and is not included in interpolation.

### Key User Settings

| Parameter | Description |
|---|---|
| `raster_dir` | Folder containing raster time-series files. |
| `shape_dir` | Folder containing tile shapefiles. |
| `raw_output_dir` | Folder where raw extracted CSV files are written. |
| `fill_output_dir` | Folder where filled CSV files are written. |
| `log_dir` | Folder where extraction and QA logs are written. |
| `raster_pattern` | Regular expression used to identify raster files. |
| `shape_prefix` | Prefix used in tile shapefile names. Default is `Centroids_`. |
| `raw_output_suffix` | Suffix for raw extracted CSV files. Default is `.csv`. |
| `fill_output_suffix` | Suffix for filled CSV files. Default is `_fill.csv`. |

### Missing-Value Filling Sequence

Missing values are filled in this order:

1. linear interpolation with `zoo::na.approx()`;
2. forward fill with `zoo::na.locf()`;
3. backward fill with `zoo::na.locf(fromLast = TRUE)`.

### Outputs

| Output | Description |
|---|---|
| `Centroids_<TileID>.csv` | Raw extracted raster values. |
| `Centroids_<TileID>_fill.csv` | Gap-filled time-series values ready for BFAST. |
| `extract_log.csv` | Per-tile extraction log. |
| `na_fill_log.csv` | Per-tile missing-value fill log. |
| `na_fill_pixel_qa_log.csv` | Pixel-level missing-value/interpolation QA log. |
| `na_fill_summary_qa_log.csv` | Tile-level missing-value summary log. |

### Recommendations

- Verify that raster files are in the correct temporal order.
- Preserve `na_fill_pixel_qa_log.csv`; the QA-enabled classification script can join this file back to classified pixels.
- Run a small tile subset before processing all tiles.
- Confirm that filled CSV structure matches the HPC BFAST input requirement.

---

## 5.3 Cleanup and Storage Management

### Script

```text
RScript_Cleanup_Extract_and_Results.r
```

### Purpose

This utility removes selected intermediate files that are no longer needed after extraction, filling, and result joining. It supports interactive cleanup modes and a dry-run option.

### Cleanup Modes

| Mode | Description |
|---|---|
| `raw_only` | Delete raw `Centroids_<TileID>.csv` files when corresponding filled files exist. |
| `unmatched_only` | Delete shapefile/result `_unmatched.csv` files. |
| `both` | Run both cleanup operations. |

### Recommendations

- Run with `dry_run <- TRUE` before deleting files.
- Keep filled CSV files until the HPC stage has completed and been verified.
- Retain mismatch reports until join quality has been reviewed.

---

## 6. Phase 2: HPC BFAST Processing

Phase 2 processes filled tile CSV files using parallel BFAST execution on an HPC cluster.

---

## 6.1 HPC Environment Note

This HPC workflow was developed and tested on Beocat, the High Performance Computing cluster at Kansas State University. The R processing scripts are portable to many Linux-based HPC environments, but scheduler directives, file paths, resource specifications, modules, and monitoring commands may require local modification.

---

## 6.2 Expected HPC Directory Structure

The HPC workflow assumes a structure similar to:

```text
~/
├── Extract/
│   ├── Centroids_80_fill.csv
│   └── Centroids_81_fill.csv
├── Output2/
├── bfastParallel_optimized_chunked.R
├── superSubmit.sh
└── singleSubmit.sh
```

---

## 6.3 BFAST Input Format

Each input CSV should contain:

- one centroid or pixel per row;
- pixel identifier in the first column;
- sequential time-series observations in all remaining columns;
- no header row unless the processing script has been modified to handle one.

---

## 6.4 Optimized Chunked BFAST Processing

### Script

```text
bfastParallel_optimized_chunked.R
```

### Purpose

Runs BFAST on tile-level CSV files using optimized parallel processing and chunked dynamic scheduling. The chunked workflow reduces scheduling overhead by assigning multiple rows to each scheduled task.

### Command-Line Usage

```bash
Rscript bfastParallel_optimized_chunked.R <number_of_cores> <input_csv> [chunk_size]
```

Examples:

```bash
Rscript bfastParallel_optimized_chunked.R 12 Extract/Centroids_80_fill.csv
Rscript bfastParallel_optimized_chunked.R 12 Extract/Centroids_80_fill.csv 500
```

### Recommended Settings

| Situation | Suggested Setting |
|---|---|
| General use | `default_chunk_size <- 500` to `1000` |
| Highly variable pixel runtimes | Smaller chunk sizes such as `250` or `500` |
| Similar pixel runtimes and high scheduler overhead | Larger chunk sizes such as `1000` |
| Confidence intervals not needed | `calculate_confint <- FALSE` |
| Confidence intervals needed for final products | `calculate_confint <- TRUE` |

---

## 6.5 Batch Job Submission

### Script

```text
superSubmit.sh
```

### Purpose

Submits BFAST jobs for all CSV files in the input directory, or for an optional numeric tile range. It skips tiles whose expected output files already exist.

### Usage

Submit all files:

```bash
bash superSubmit.sh
```

Submit only a tile range:

```bash
bash superSubmit.sh 80 120
```

---

## 6.6 Single-Tile Job Submission

### Script

```text
singleSubmit.sh
```

### Usage

```bash
bash singleSubmit.sh Centroids_80_fill.csv
```

Use this script for testing, reprocessing failed tiles, or checking parameter changes before batch submission.

---

## 6.7 BFAST Output Products

Each processed tile can produce the following files:

| Output File | Description |
|---|---|
| `*_trend_breaks_time.txt` | Timing of detected trend breaks. |
| `*_trend_breaks_magnitude.txt` | Magnitude of detected trend breaks. |
| `*_trend_nbbreaks.txt` | Number of trend breaks. |
| `*_trend_bfast.txt` | Fitted trend component values. |
| `*_season_nbbreaks.txt` | Number of seasonal breaks. |
| `*_season_breaks_time.txt` | Timing of seasonal breaks. |
| `*_season_bfast.txt` | Fitted seasonal component values. |
| `*_trend_breaks_confint.txt` | Trend breakpoint confidence intervals. |
| `*_season_breaks_confint.txt` | Seasonal breakpoint confidence intervals. |
| `*_nobs.txt` | Number of valid observations used by BFAST. |

---

## 6.8 Monitoring and Management

Common SLURM commands include:

| Command | Purpose |
|---|---|
| `squeue -u <username>` | Monitor active jobs. |
| `scancel <jobid>` | Cancel a running job. |

On Beocat, local commands such as `kstat --me` may also be available.

---

## 7. Phase 3: QA-Enabled Post-Processing and Product Generation

Phase 3 reconstructs BFAST outputs, assigns ecological classes, joins results to spatial features, verifies processing completion, creates progress maps, converts joined point results to rasters, and mosaics tile rasters into regional products.

Recommended order:

1. Reconstruct, classify, and join BFAST results.
2. Verify processing completion.
3. Visualize processing status.
4. Create tile-level raster products.
5. Build regional mosaics.

---

## 7.1 Reconstruct, Classify, and Join BFAST Results

### Script

```text
RScript_BFASTResults_And_Join_Folder_QA.R
```

### Purpose

This end-to-end QA script reads BFAST output files for complete tiles, reconstructs per-tile result CSVs, estimates trend slope and p-value, assigns the current 11-class ecological framework, joins results back to centroid shapefiles, and writes processing, mismatch, pixel accounting, and dropped-pixel reason logs.

The join uses:

- shapefile field: `pointid`
- result field: `ID`

The script joins by ID rather than row order.

### Key User Settings

| Parameter | Description |
|---|---|
| `input_dir` | Folder containing BFAST output text files from the HPC run. |
| `result_output_dir` | Folder where reconstructed result CSV files are written. |
| `shape_dir` | Folder containing original tile centroid shapefiles. |
| `join_output_dir` | Folder where joined shapefiles and mismatch reports are written. |
| `log_dir` | Folder where processing, join, accounting, and dropped-pixel logs are written. |
| `periods_per_season` | Number of observations per seasonal cycle. Current value: `23`. |
| `alpha` | Classification significance threshold. Current value: `0.05`. |
| `small_magnitude_threshold` | Small magnitude threshold. Current value: `0.03`. |
| `large_magnitude_threshold` | Large magnitude threshold. Current value: `0.07`. |
| `recovery_magnitude_threshold` | Minimum negative magnitude for recovery proxy. Current value: `0.03`. |
| `recovery_slope_threshold` | Recovery slope threshold. Current value: `0`. |
| `recovery_require_significant_slope` | Whether recovery requires significant positive slope. Current value: `TRUE`. |
| `high_break_count` | Break-count threshold for highly dynamic class. Current value: `4`. |
| `missing_output_value` | Numeric NoData value. Current value: `-9999`. |

### Optional Interpolation QA Settings

| Parameter | Current Value | Purpose |
|---|---:|---|
| `fill_pct_moderate_threshold` | 0.05 | Moderate interpolation threshold. |
| `fill_pct_excessive_threshold` | 0.20 | Excessive interpolation threshold. |
| `fill_pct_severe_threshold` | 0.50 | Severe interpolation threshold. |
| `max_gap_moderate_threshold` | 5 | Moderate maximum-gap threshold. |
| `max_gap_excessive_threshold` | 20 | Excessive maximum-gap threshold. |
| `max_gap_severe_threshold` | 50 | Severe maximum-gap threshold. |
| `exclude_excessively_interpolated_from_classification` | `FALSE` | Flags excessive interpolation without suppressing class assignment by default. |

### Main Outputs

| Output | Description |
|---|---|
| `<tile>_results.csv` | Reconstructed per-tile BFAST result table with classification and QA fields. |
| `Centroids_<tile>_Result.shp` | Joined GIS-ready tile shapefile. |
| `Centroids_<tile>_shape_unmatched.csv` | Shapefile features not found in results. |
| `Centroids_<tile>_result_unmatched.csv` | Result rows not found in shapefile. |
| `bfast_results_log.csv` | Tile-level processing summary with class, trend, QA, and mass-balance fields. |
| `bfast_trend_cumulative.csv` | Cumulative summary of successful tiles. |
| `join_results_log.csv` | Shapefile/result join accounting. |
| `pixel_accounting_log.csv` | Cross-stage accounting of retained, missing, flagged, and unmatched pixels. |
| `dropped_pixel_reason_log.csv` | Per-pixel reason log for missing inputs, warnings, interpolation QA, Class 11, and join mismatches. |

### Recommendations

- Review `pixel_accounting_log.csv` and `dropped_pixel_reason_log.csv` before raster creation.
- Do not delete mismatch reports until join quality has been reviewed.
- Review Class 11 frequencies before publication.
- Treat trend warnings as QA metadata, not as a separate ecological class.
- Retain CSV/log outputs as the authoritative record because shapefile field-name limits can truncate attributes.

---

## 7.2 Verify Processing Completion

### Script

```text
RScript_Build_MasterProcessingLog.R
```

### Purpose

Combines the fishnet tile list with extraction, NA-fill, BFAST, and join logs to create a master processing summary and a progress summary.

### Outputs

| Output | Description |
|---|---|
| `Fishnet50K_processing_summary.csv` | Master tile-level processing summary. |
| `Fishnet50K_processing_progress.csv` | Progress summary table for reporting or mapping. |

---

## 7.3 Visualize Processing Status

### Script

```text
RScript_BFASTProgressMap.r
```

### Purpose

Creates a shapefile that joins processing completion status to the fishnet grid, allowing processing progress to be mapped spatially.

---

## 7.4 Create Tile-Level Raster Products

### Script

```text
PythonScript_CreateResultRasters_QA.py
```

### Purpose

Converts joined point-based BFAST result shapefiles into raster tiles for selected output fields. The QA version supports the 11-class classification system, trend codes, interpolation QA rasters, categorical labels, processed logs, and a run summary log.

### Supported Value Fields

The script supports the following field menu. Some shapefile fields may use truncated names because of ESRI Shapefile field-name limits.

| Field | Description |
|---|---|
| `T_NBR` | Number of trend breaks. |
| `T_SEASO` | Trend break season; truncated from `T_SEASON`. |
| `T_PERIO` | Trend break period; truncated from `T_PERIOD`. |
| `T_MAG` | Trend break magnitude. |
| `T_SLOPE` | Trend slope. |
| `PVALUE` | Trend model p-value. |
| `TREND` | Trend direction class, rasterized as -1, 0, 1, or -9999. |
| `S_NBR` | Number of seasonal breaks. |
| `S_SEASO` | Seasonal break season; truncated from `S_SEASON`. |
| `CLASS` | Numeric ecological class. |
| `LABEL` | Text ecological label, converted to numeric class value for rasterization. |
| `NOBS` | Number of valid observations. |
| `INTERP_P` | Interpolation percentage/fraction; truncated from `INTERP_PCT`. |
| `INTERP_C` | Interpolation class; truncated from `INTERP_CLASS`. |
| `T_CI_LOW`, `T_CI_EST`, `T_CI_UPP` | Trend breakpoint confidence interval values. |
| `S_CI_LOW`, `S_CI_EST`, `S_CI_UPP` | Seasonal breakpoint confidence interval values. |

### Outputs

| Output | Description |
|---|---|
| `<tile>_<FIELD>.tif` | Tile raster for one BFAST output field. |
| `CreateResultRasters_<FIELD>_processed.txt` | Per-field processed raster log. |
| `CreateResultRasters_INTERP_QA_run_summary.csv` | Raster creation run summary. |

---

## 7.5 Build Regional Mosaics

### Script

```text
PythonScript_MosaicResultRasters_QA.py
```

### Purpose

Mosaics tile-level raster outputs into larger regional rasters for each requested BFAST output field. The QA version supports 11-class labels, interpolation class labels, trend class labels, true NoData cleanup, and per-field processed logs.

### Outputs

| Output | Description |
|---|---|
| `Mosaic_<FIELD>.tif` | Regional mosaic raster for one selected BFAST output field. |
| `Mosaic_<FIELD>_processed.txt` | Per-field record of rasters already included in the mosaic. |
| `MosaicResultRasters_INTERP_QA_run_summary.csv` | Mosaic creation/update summary. |

---

## 8. Classification and Output Field Reference

### Ecological Classes

| Code | Label | Interpretation |
|---:|---|---|
| 1 | Stable grassland | No trend break and stable trend. |
| 2 | Climate-driven variability | Breakpoint behavior with weak, stable, non-significant, or small-magnitude trend signal. |
| 3 | Abrupt decline | Significant negative trend with one or more breaks and magnitude at or above 0.03. |
| 4 | Recovery trajectory | Multiple breaks, negative break magnitude, positive slope, and significant slope when required. |
| 5 | Sustained degradation | Multiple breaks, significant negative trend, and magnitude at or above 0.07. |
| 6 | Sustained improvement | Significant positive trend with at least one break and magnitude at or above 0.03. |
| 7 | Phenological shift | Seasonal break with no trend break. |
| 8 | Highly dynamic | Trend break count at or above 4. |
| 9 | Gradual decline | Significant negative slope with no trend break. |
| 10 | Gradual improvement | Significant positive slope with no trend break. |
| 11 | Other | Valid BFAST combination not captured by earlier rules. |
| -9999 | Missing/NoData | Required classification inputs are missing, or optional QA exclusion was applied. |

### Trend Direction Encoding

| TREND | Code |
|---|---:|
| Negative | -1 |
| Stable | 0 |
| Positive | 1 |
| Missing/NoData | -9999 |

### Interpolation QA Encoding

| `INTERP_CLASS` | Label |
|---:|---|
| 0 | No interpolation |
| 1 | Minor interpolation |
| 2 | Moderate interpolation |
| 3 | Excessive interpolation |
| 4 | Severe interpolation |
| -9999 | NoData |

---

## 9. QA/QC Logs and Restart-Safe Design

This workflow is designed for large analyses that may require repeated runs, job recovery, or incremental updates.

### Restart-Safe Features

| Stage | Restart-Safe Mechanism |
|---|---|
| Tile creation | Existing tile shapefiles are skipped. |
| Extraction | Tiles marked `SUCCESS` in `extract_log.csv` are skipped. |
| HPC submission | Jobs are skipped when expected outputs already exist. |
| Result reconstruction/classification | Tiles marked `SUCCESS` in `bfast_results_log.csv` are skipped. |
| Raster creation | Per-field processed logs prevent duplicate raster creation. |
| Mosaicking | Per-field processed logs track rasters already added to mosaics. |

### QA Logs

| Log | Purpose |
|---|---|
| `extract_log.csv` | Tracks tile-level extraction status. |
| `na_fill_log.csv` | Tracks tile-level missing-value filling. |
| `na_fill_pixel_qa_log.csv` | Pixel-level interpolation QA. |
| `na_fill_summary_qa_log.csv` | Tile-level interpolation QA summary. |
| `bfast_results_log.csv` | Result reconstruction, class counts, trend counts, QA counts, and mass-balance fields. |
| `bfast_trend_cumulative.csv` | Cumulative summary of successful tile rows. |
| `join_results_log.csv` | Shapefile/result join status and mismatch counts. |
| `pixel_accounting_log.csv` | Tile-level retained/missing/flagged/unmatched pixel accounting. |
| `dropped_pixel_reason_log.csv` | Per-pixel reason log for missing inputs, trend warnings, interpolation QA, Class 11, and join mismatches. |
| `Fishnet50K_processing_summary.csv` | Master processing summary. |
| `Fishnet50K_processing_progress.csv` | Progress summary. |
| `CreateResultRasters_INTERP_QA_run_summary.csv` | Raster creation summary. |
| `MosaicResultRasters_INTERP_QA_run_summary.csv` | Mosaic creation/update summary. |

---

## 10. Suggested Troubleshooting Checks

### Before Phase 1

- Confirm all raster files are in the correct temporal order.
- Confirm centroid features include `pointid`.
- Confirm fishnet polygons include the tile field used by the scripts.
- Confirm all paths are updated in the user settings sections.

### Before Phase 2

- Confirm filled CSV files exist in the HPC `Extract/` directory.
- Confirm `outputDir` is consistent across submission and BFAST scripts.
- Confirm required R packages are available on compute nodes.
- Run one tile with `singleSubmit.sh` before launching all tiles.

### Before Phase 3

- Confirm all expected BFAST output files have been downloaded.
- Confirm filename suffixes match `RScript_BFASTResults_And_Join_Folder_QA.R`.
- Confirm original tile shapefiles are available for joining.
- Review mismatch CSV files before deleting them.
- Review `pixel_accounting_log.csv` and `dropped_pixel_reason_log.csv` before raster creation.
- Use a consistent `template_raster` for raster creation and mosaicking.

### Common Issues

| Issue | Likely Cause | Suggested Check |
|---|---|---|
| Tile skipped unexpectedly | Log marks it complete or output exists | Review log and output folder. |
| Join mismatch files contain many records | ID mismatch between shapefile and result table | Check `pointid` and `ID` values. |
| High Class 11 counts | Valid combinations not captured by current rules | Review thresholds and spatial clustering. |
| Raster field missing | Joined shapefile does not contain requested or truncated field | Check field names and `value_fields`. |
| Mosaic does not update | Processed log already lists rasters | Review or reset `Mosaic_<FIELD>_processed.txt`. |
| HPC job exits early | Missing R package or incorrect path | Check SLURM output and script paths. |

---

## 11. Documentation, Citation, and License

Detailed manuals are provided in:

```text
docs/BFAST_Grassland_Classification_Workflow_Manual_v3.docx
docs/BFAST_Classification_Technical_Manual_v3.docx
```

If you use this workflow in a publication, report, thesis, dissertation, or derivative software project, please cite this repository and the original BFAST methodology. Citation metadata are provided in `CITATION.cff`.

This repository is distributed under the GNU General Public License v3.0. See `LICENSE`.
