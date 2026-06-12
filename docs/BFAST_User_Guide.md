# BFAST Processing Framework User Guide

A comprehensive operational guide for preprocessing, HPC-based BFAST analysis, and post-processing of large remote sensing time-series datasets.

---

## Table of Contents

- [1. Purpose and Scope](#1-purpose-and-scope)
- [2. Workflow Overview](#2-workflow-overview)
- [3. Recommended Repository Layout](#3-recommended-repository-layout)
- [4. Software Requirements](#4-software-requirements)
- [5. Phase 1: Preprocessing on a Workstation](#5-phase-1-preprocessing-on-a-workstation)
  - [5.1 Create Tile Shapefiles](#51-create-tile-shapefiles)
  - [5.2 Extract Raster Time Series and Fill Missing Values](#52-extract-raster-time-series-and-fill-missing-values)
  - [5.3 Cleanup and Storage Management](#53-cleanup-and-storage-management)
- [6. Phase 2: High Performance Computing Processing](#6-phase-2-high-performance-computing-processing)
  - [6.1 HPC Environment Note](#61-hpc-environment-note)
  - [6.2 Expected HPC Directory Structure](#62-expected-hpc-directory-structure)
  - [6.3 BFAST Input Format](#63-bfast-input-format)
  - [6.4 Optimized Chunked BFAST Processing](#64-optimized-chunked-bfast-processing)
  - [6.5 Batch Job Submission](#65-batch-job-submission)
  - [6.6 Single-Tile Job Submission](#66-single-tile-job-submission)
  - [6.7 BFAST Output Products](#67-bfast-output-products)
  - [6.8 Monitoring and Management](#68-monitoring-and-management)
- [7. Phase 3: Post-Processing and Product Generation](#7-phase-3-post-processing-and-product-generation)
  - [7.1 Reconstruct and Join BFAST Results](#71-reconstruct-and-join-bfast-results)
  - [7.2 Verify Processing Completion](#72-verify-processing-completion)
  - [7.3 Visualize Processing Status](#73-visualize-processing-status)
  - [7.4 Create Tile-Level Raster Products](#74-create-tile-level-raster-products)
  - [7.5 Build Regional Mosaics](#75-build-regional-mosaics)
- [8. Output Field Reference](#8-output-field-reference)
- [9. Reproducibility and Restart-Safe Design](#9-reproducibility-and-restart-safe-design)
- [10. Suggested Troubleshooting Checks](#10-suggested-troubleshooting-checks)
- [11. Citation and License Guidance](#11-citation-and-license-guidance)

---

## 1. Purpose and Scope

This guide documents a complete workflow for running large-scale BFAST analyses on remote sensing time-series data. The scripts are designed for workflows in which raster values are extracted at centroid or pixel locations, split into spatial tiles, processed in parallel on an HPC system, and reconstructed into spatial products for mapping and analysis.

The documentation is organized around the actual processing sequence:

1. **Preprocessing on a local workstation**
2. **BFAST processing on an HPC cluster**
3. **Post-processing and product generation on a local workstation**

Each script section includes:

- Purpose
- Inputs
- User settings
- Process summary
- Outputs
- Recommendations and notes

---

## 2. Workflow Overview

```text
Input spatial data
├── Raster time series
├── Centroid point feature class
└── Fishnet tile grid
        ↓
Phase 1: Preprocessing
├── Create one centroid shapefile per tile
├── Extract raster values for each centroid
├── Fill missing values
└── Write BFAST-ready tile CSV files and QA logs
        ↓
Phase 2: HPC Processing
├── Transfer filled CSV files to HPC Extract/
├── Submit SLURM jobs using singleSubmit.sh or superSubmit.sh
├── Run optimized BFAST processing in parallel
└── Write one group of output text files per tile
        ↓
Phase 3: Post-Processing
├── Reconstruct per-tile BFAST result tables
├── Join results to tile shapefiles
├── Build master processing logs
├── Create processing progress maps
├── Convert joined point results to rasters
└── Mosaic tile rasters into regional products
```

---

## 3. Recommended Repository Layout

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
- Required R packages available on compute nodes

---

## 5. Phase 1: Preprocessing on a Workstation

Phase 1 prepares the tile-level time-series inputs that will be submitted to the HPC environment.

---

## 5.1 Create Tile Shapefiles

### Script

```text
PythonScript_CreateTileShapefiles.py
```

### Purpose

This script partitions a large centroid dataset into tile-specific shapefiles using a fishnet grid. Each fishnet polygon is used to select intersecting centroid points, and the selected points are exported as a separate shapefile named by tile number.

### Inputs

- A point feature class containing centroid or pixel locations.
- A fishnet polygon feature class defining spatial processing tiles.
- A tile identifier field in the fishnet layer.
- An output folder for tile shapefiles.

### User Settings

| Parameter | Description |
|---|---|
| `arcpy.env.workspace` | ArcGIS workspace or geodatabase containing source feature classes. |
| `arcpy.env.overwriteOutput` | Whether ArcPy may overwrite existing outputs. The script sets this to `True`. |
| `points_fc` | Input point feature class containing centroid locations. |
| `fishnet_fc` | Fishnet polygon feature class used to define processing tiles. |
| `out_folder` | Folder where tile shapefiles are written. |
| `tile_field` | Attribute field in the fishnet layer containing tile identifiers. |

### Process Summary

1. Create feature layers for the point and fishnet datasets.
2. Iterate through each fishnet polygon.
3. Select points intersecting the current polygon.
4. Export the selected points as `Centroids_<tile>.shp`.
5. Skip existing outputs to avoid unnecessary reprocessing.
6. Report the number of tile shapefiles created.

### Outputs

```text
Centroids_<tile>.shp
```

Example:

```text
Centroids_80.shp
Centroids_81.shp
Centroids_82.shp
```

### Recommendations

- Ensure the point and fishnet layers use compatible coordinate systems.
- Confirm that `tile_field` contains unique tile identifiers.
- Use a local drive or fast storage for large shapefile exports.
- Keep tile names consistent because later scripts parse tile numbers from names beginning with `Centroids_`.

---

## 5.2 Extract Raster Time Series and Fill Missing Values

### Script

```text
RScript_ExtractAndFill_Folder_with_QA.r
```

### Purpose

This script extracts a time series of raster values at each centroid location, writes raw extraction CSV files, fills missing values, writes filled CSV files, and creates multiple QA logs.

The first output column is the shapefile field `pointid`. This field is preserved unchanged and is not included in interpolation.

### Inputs

- A folder of raster time-series files.
- A folder of tile shapefiles named like `Centroids_277.shp`.
- Each tile shapefile must contain a `pointid` field.
- Output and log folders.

### User Settings

| Parameter | Description |
|---|---|
| `raster_dir` | Folder containing the raster time-series files. |
| `shape_dir` | Folder containing tile shapefiles. |
| `output_dir` | Folder where raw and filled CSV outputs are written. |
| `log_dir` | Folder where extraction and QA logs are written. |
| `raster_pattern` | Regular expression used to identify raster files. Default pattern matches `.tif` files. |
| `shape_prefix` | Prefix used in tile shapefile names. Default is `Centroids_`. |
| `shape_pattern` | Regular expression used to identify tile shapefiles. |
| `include_pointid_column` | Whether to include the `pointid` field as the first output column. |
| `raw_output_suffix` | Suffix for raw extracted CSV files. Default is `.csv`. |
| `fill_output_suffix` | Suffix for filled CSV files. Default is `_fill.csv`. |
| `extract_log_file` | CSV log tracking extraction status by tile. |
| `na_fill_log_file` | CSV log tracking missing-value filling status by tile. |
| `na_fill_pixel_qa_log_file` | Pixel-level QA log describing missing-value replacement. |
| `na_fill_summary_qa_log_file` | Tile-level summary QA log describing missing-value replacement. |

### Process Summary

For each tile shapefile:

1. Read centroid points.
2. Build a raster stack from files matching `raster_pattern`.
3. Extract raster values at point locations.
4. Write a raw extraction CSV.
5. Detect missing values across time-series columns.
6. Fill missing values in sequence:
   - Linear interpolation using `zoo::na.approx()`
   - Forward fill using `zoo::na.locf()`
   - Backward fill using `zoo::na.locf(fromLast = TRUE)`
7. Write the filled CSV.
8. Append extraction, filling, pixel-level QA, and summary QA logs.
9. Skip tiles already marked `SUCCESS` in `extract_log.csv`.

### Outputs

| Output | Description |
|---|---|
| `Centroids_<tile>.csv` | Raw extracted raster values. |
| `Centroids_<tile>_fill.csv` | Gap-filled time-series values ready for BFAST. |
| `extract_log.csv` | Per-tile extraction log. |
| `na_fill_log.csv` | Per-tile missing-value fill log. |
| `na_fill_pixel_qa_log.csv` | Pixel-level QA log. |
| `na_fill_summary_qa_log.csv` | Tile-level missing-value summary log. |

### Recommendations

- Verify raster files are correctly ordered before extraction.
- Preserve the QA logs with final outputs.
- Run a small tile subset before processing all tiles.
- Confirm that output CSV structure matches the BFAST input requirement: first column ID, remaining columns time-series values, no header row if required by the HPC workflow.

---

## 5.3 Cleanup and Storage Management

### Script

```text
RScript_Cleanup_Extract_and_Results.r
```

### Purpose

This utility removes intermediate files that are no longer needed after extraction, filling, and joining. It supports interactive cleanup modes and a dry-run option.

### User Settings

| Parameter | Description |
|---|---|
| `extract_dir` | Folder containing extraction CSV files. |
| `results_dir` | Folder containing joined result files and mismatch reports. |
| `prefix` | Filename prefix used for tile outputs. Default is `Centroids_`. |
| `fill_suffix` | Suffix used for filled CSV files. Default is `_fill.csv`. |
| `dry_run` | If `TRUE`, preview deletions without deleting files. If `FALSE`, files are deleted. |

### Cleanup Modes

The script prompts for one of three modes:

| Mode | Description |
|---|---|
| `raw_only` | Delete `Centroids_<tile>.csv` when the corresponding `Centroids_<tile>_fill.csv` exists. |
| `unmatched_only` | Delete files ending in `_unmatched.csv`. |
| `both` | Run both cleanup operations. |

### Outputs

This script does not create analytical outputs. It reports counts of deleted files and helps reduce storage use.

### Recommendations

- Run with `dry_run <- TRUE` first when adapting the script to a new project.
- Keep filled CSV files until the HPC phase has been completed and verified.
- Retain mismatch reports until joins have been reviewed.

---

## 6. Phase 2: High Performance Computing Processing

Phase 2 processes filled tile CSV files using parallel BFAST execution on an HPC cluster.

---

## 6.1 HPC Environment Note

> **Note:** This HPC workflow was developed and tested on **Beocat**, the High Performance Computing cluster at Kansas State University. While the R processing scripts are portable to most Linux-based HPC environments, some submission scripts, scheduler directives, file paths, resource specifications, node constraints, and monitoring commands may require modification for other systems.

---

## 6.2 Expected HPC Directory Structure

The HPC workflow assumes a structure similar to:

```text
~/
├── Extract/
│   ├── Centroids_80_fill.csv
│   └── Centroids_81_fill.csv
├── Output2/
├── bfastParallel.sh
├── bfastParallel_optimized_chunked.R
├── superSubmit.sh
└── singleSubmit.sh
```

The folder name in the submission scripts is configurable through `inputDir` and `outputDir`.

---

## 6.3 BFAST Input Format

Each input CSV should contain:

- One centroid or pixel per row.
- Pixel identifier in the first column.
- Sequential time-series observations in all remaining columns.
- No header row, unless the processing script is modified to handle one.

Example structure:

```text
pointid,t1,t2,t3,...,tn
```

In the actual no-header input format, the first row should contain data, not column names.

---

## 6.4 Optimized Chunked BFAST Processing

### Script

```text
bfastParallel_optimized_chunked.R
```

### Purpose

Runs BFAST on tile-level CSV files using optimized parallel processing and chunked dynamic scheduling. The chunked workflow reduces parallel scheduling overhead by assigning multiple rows to each scheduled task.

### User Settings

| Parameter | Description |
|---|---|
| `annual_image_frequency` | Number of observations per year in the time series. The current script uses `23`. |
| `tsdata_start_year` | First year represented by the time series. The current script uses `2001`. |
| `bfast_h` | Minimum segment size used by BFAST. The script supports values such as `"rdist"` or numeric values such as `0.15`. |
| `bfast_season` | Seasonal model passed to BFAST. Options include `"harmonic"`, `"dummy"`, or `"none"`. |
| `bfast_max_iter` | Maximum number of BFAST iterations. The script recommends `1`. |
| `calculate_confint` | Whether to calculate breakpoint confidence intervals. Confidence intervals can be expensive. |
| `output_dir` | Folder where BFAST output files are written. |
| `default_chunk_size` | Number of rows assigned to each scheduled parallel task when no command-line chunk size is provided. |

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

### Process Summary

1. Read command-line arguments.
2. Load the tile CSV.
3. Treat the first column as the ID field.
4. Convert remaining columns to numeric time-series values.
5. Precompute valid observation counts.
6. Split rows into chunks.
7. Run BFAST in parallel across chunks.
8. Extract trend, seasonal, residual, confidence interval, and observation-count outputs.
9. Write each output file once.

### Outputs

See [BFAST Output Products](#67-bfast-output-products).

---

## 6.5 Batch Job Submission

### Script

```text
superSubmit.sh
```

### Purpose

Submits BFAST jobs for all CSV files in the input directory, or for an optional numeric tile range. It skips tiles whose expected output files already exist.

### User Settings

| Parameter | Description |
|---|---|
| `numCores` | Number of cores requested for each job. |
| `memoryPerCpu` | Memory requested per CPU. |
| `outputDir` | Folder where BFAST output files are written. |
| `inputDir` | Folder containing input CSV files. |

### Usage

Submit all files:

```bash
bash superSubmit.sh
```

Submit only a tile range:

```bash
bash superSubmit.sh 80 120
```

### Process Summary

1. Identify CSV files in `inputDir`.
2. Optionally filter by tile range.
3. Parse tile numbers from filenames.
4. Check whether expected BFAST outputs already exist in `outputDir`.
5. Calculate walltime from file size.
6. Submit each incomplete tile using `sbatch`.

### Restart-Safe Behavior

The script checks for expected output files before submitting a job. If all required outputs exist and are non-empty, the tile is skipped.

---

## 6.6 Single-Tile Job Submission

### Script

```text
singleSubmit.sh
```

### Purpose

Submits one selected tile CSV for BFAST processing and skips processing if expected output files already exist.

### User Settings

| Parameter | Description |
|---|---|
| `numCores` | Number of cores requested for the job. |
| `memoryPerCpu` | Memory requested per CPU. |
| `outputDir` | Folder where BFAST output files are written. |
| `inputDir` | Folder containing input CSV files. |

### Usage

```bash
bash singleSubmit.sh Centroids_80_fill.csv
```

### Recommendations

Use this script for:

- Testing a single tile.
- Reprocessing failed tiles.
- Checking parameter changes before batch submission.

---

## 6.7 BFAST Output Products

Each processed tile can produce the following files:

| Output File | Description |
|---|---|
| `*_trend_breaks_time.txt` | Timing of detected trend breaks. |
| `*_trend_breaks_magnitude.txt` | Magnitude of detected trend breaks. |
| `*_trend_nbbreaks.txt` | Number of trend breaks. |
| `*_trend_bfast.txt` | Trend component values. |
| `*_season_nbbreaks.txt` | Number of seasonal breaks. |
| `*_season_breaks_time.txt` | Timing of seasonal breaks. |
| `*_season_bfast.txt` | Seasonal component values. |
| `*_trend_breaks_confint.txt` | Trend breakpoint confidence intervals. |
| `*_season_breaks_confint.txt` | Seasonal breakpoint confidence intervals. |
| `*_residuals_bfast.txt` | Residual or remainder component values. |
| `*_nobs.txt` | Number of valid observations used by BFAST. |

---

## 6.8 Monitoring and Management

The commands below are specific to Beocat and may differ on other HPC systems.

| Command | Purpose |
|---|---|
| `kstat --me` | Monitor active jobs submitted under your account. |
| `kstat -j <jobid>` | View details for a specific job. |
| `kstat -c <username>` | Review resource use by user. |
| `kstat -d 10` | View recent jobs. |
| `scancel <jobid>` | Cancel a running SLURM job. |

Researchers adapting the workflow to another cluster should consult local HPC documentation for equivalent monitoring and accounting commands.

---

## 7. Phase 3: Post-Processing and Product Generation

Phase 3 reconstructs BFAST output files, joins them to spatial features, verifies processing completion, creates progress maps, converts joined point results to rasters, and mosaics tile rasters into regional products.

The recommended order is:

1. Reconstruct and join BFAST results.
2. Verify processing completion.
3. Visualize processing status.
4. Create tile-level raster products.
5. Build regional mosaics.

---

## 7.1 Reconstruct and Join BFAST Results

### Script

```text
RScript_BFASTResults_And_Join_Folder.R
```

### Purpose

This end-to-end script reads BFAST output files for all complete tiles, reconstructs a per-tile summary CSV, classifies results, joins results back to matching centroid shapefiles, writes joined result shapefiles, and creates QA logs.

The join uses:

- Shapefile field: `pointid`
- Results field: `ID`

### User Settings

| Parameter | Description |
|---|---|
| `input_dir` | Folder containing BFAST output text files from the HPC run. |
| `result_output_dir` | Folder where reconstructed tile result CSV files are written. |
| `shape_dir` | Folder containing original tile centroid shapefiles. |
| `join_output_dir` | Folder where joined result shapefiles and mismatch reports are written. |
| `log_dir` | Folder where processing and join logs are written. |
| `suffix_nobs` | Filename suffix for NOBS output. |
| `suffix_season_bfast` | Filename suffix for seasonal component output. |
| `suffix_season_confint` | Filename suffix for seasonal confidence interval output. |
| `suffix_season_breaktime` | Filename suffix for seasonal breakpoint timing output. |
| `suffix_season_nbbreaks` | Filename suffix for number of seasonal breakpoints. |
| `suffix_trend_bfast` | Filename suffix for trend component output. |
| `suffix_trend_confint` | Filename suffix for trend confidence interval output. |
| `suffix_trend_breakmag` | Filename suffix for trend break magnitude output. |
| `suffix_trend_breaktime` | Filename suffix for trend breakpoint timing output. |
| `suffix_trend_nbbreaks` | Filename suffix for number of trend breakpoints. |
| `result_suffix` | Suffix for reconstructed result CSV files. |
| `shape_prefix` | Prefix used for tile shapefiles. |
| `shape_out_suffix` | Suffix used for joined output shapefiles. |
| `shape_mismatch_suffix` | Suffix for records present in shapefile but not results. |
| `result_mismatch_suffix` | Suffix for records present in results but not shapefile. |
| `periods_per_season` | Number of observations per seasonal cycle. |
| `pvalue_threshold` | Statistical threshold used in trend summaries. |
| `alpha` | Significance level used by classification rules. |
| `small_magnitude_threshold` | Threshold for small trend-break magnitude. |
| `large_magnitude_threshold` | Threshold for large trend-break magnitude. |
| `recovery_magnitude_threshold` | Magnitude threshold used for recovery/resilience classification. |
| `recovery_slope_threshold` | Slope threshold used for recovery/resilience classification. |
| `recovery_require_significant_slope` | Whether recovery classification requires significant positive slope. |
| `high_break_count` | Break-count threshold used to identify highly dynamic or unstable behavior. |
| `process_log_file` | Log of BFAST result reconstruction status. |
| `trend_cumulative_file` | Cumulative trend totals CSV. |
| `join_summary_log_file` | Log of shapefile join status and QA information. |

### Process Summary

1. Identify tiles with a complete set of BFAST outputs.
2. Skip tiles already marked `SUCCESS` in `bfast_results_log.csv`.
3. Read trend, seasonal, confidence interval, and NOBS outputs.
4. Reconstruct a tile-level result table.
5. Calculate trend metrics, p-values, trend labels, and classification labels.
6. Write a tile result CSV.
7. Read the matching centroid shapefile.
8. Verify unique join keys.
9. Join results to shapefile features by `pointid` and `ID`.
10. Write a joined shapefile ending in `_Result.shp`.
11. Write mismatch reports for QA.
12. Append process and join logs.

### Outputs

| Output | Description |
|---|---|
| `<tile>_results.csv` | Reconstructed per-tile BFAST summary table. |
| `Centroids_<tile>_Result.shp` | Joined GIS-ready tile shapefile. |
| `Centroids_<tile>_shape_unmatched.csv` | Shapefile records not matched to result records. |
| `Centroids_<tile>_result_unmatched.csv` | Result records not matched to shapefile records. |
| `bfast_results_log.csv` | Result reconstruction log. |
| `bfast_trend_cumulative.csv` | Cumulative trend summary. |
| `join_results_log.csv` | Join summary and QA log. |

### Recommendations

- Do not delete mismatch reports until they have been reviewed.
- Verify that `pointid` is unique in each shapefile.
- Verify that `ID` is unique in reconstructed results.
- Run this script before raster generation; raster scripts expect joined result shapefiles.

---

## 7.2 Verify Processing Completion

### Script

```text
RScript_Build_MasterProcessingLog.R
```

### Purpose

Combines the fishnet tile list with extraction, NA-fill, BFAST, and join logs to create a master processing summary and a progress summary.

### Inputs

- Fishnet tile list CSV.
- Extraction log.
- NA-fill log.
- BFAST results log.
- Join log.

### User Settings

| Parameter | Description |
|---|---|
| `log_dir` | Folder containing workflow logs. |
| `fishnet_file` | CSV listing all fishnet tiles. |
| `extract_log_file` | Extraction log created in Phase 1. |
| `na_fill_log_file` | Missing-value fill log created in Phase 1. |
| `bfast_log_file` | BFAST reconstruction log created in Phase 3. |
| `join_log_file` | Join summary log created in Phase 3. |
| `master_output_file` | Output master processing summary CSV. |
| `progress_output_file` | Output progress summary CSV. |

### Process Summary

1. Read all available input logs.
2. Standardize tile identifiers.
3. Keep the latest log record per tile.
4. Prefix log fields by workflow stage.
5. Join all logs to the fishnet tile list.
6. Calculate completed processing steps.
7. Write master and progress summaries.

### Outputs

| Output | Description |
|---|---|
| `Fishnet50K_processing_summary.csv` | Master tile-level processing summary. |
| `Fishnet50K_processing_progress.csv` | Progress summary table for reporting or mapping. |

### Recommendations

- Run this after reconstructing and joining BFAST results.
- Use the master summary to identify missing or incomplete tiles.
- Archive this file with final outputs as a project audit record.

---

## 7.3 Visualize Processing Status

### Script

```text
RScript_BFASTProgressMap.r
```

### Purpose

Creates a shapefile that joins processing completion status to the fishnet grid, allowing processing progress to be mapped spatially.

### User Settings

| Parameter | Description |
|---|---|
| `summary_csv` | Master processing summary CSV, usually `Fishnet50K_processing_summary.csv`. |
| `fishnet_shp` | Fishnet shapefile containing a `Tile` field. |
| `timestamp` | Timestamp used to create unique output names. |
| `out_base` | Base path for the timestamped output progress shapefile. |
| `output_shp` | Full path for the output progress shapefile. |

### Required Fields

| Dataset | Required Field |
|---|---|
| Summary CSV | `tile` |
| Summary CSV | `completed_steps` |
| Fishnet shapefile | `Tile` |

### Process Summary

1. Read the master processing summary CSV.
2. Read the fishnet shapefile.
3. Validate required fields.
4. Join completion status to fishnet polygons by tile number.
5. Replace missing completion values with zero.
6. Write a timestamped progress shapefile.

### Outputs

```text
Progress_<timestamp>.shp
```

### Recommendations

- Symbolize the output by `comp_step`.
- Use this map to identify spatial clusters of missing or failed processing.
- Re-run after updating the master processing log.

---

## 7.4 Create Tile-Level Raster Products

### Script

```text
PythonScript_CreateResultRasters.py
```

### Purpose

Converts joined point-based BFAST result shapefiles into raster tiles for selected output fields. The script writes per-field processed logs and a run summary CSV.

### User Settings

| Parameter | Description |
|---|---|
| `input_folder` | Folder containing joined BFAST result shapefiles. |
| `output_folder` | Folder where tile raster outputs are written. |
| `template_raster` | Raster used to define snap raster, cell size, coordinate system, and spatial alignment. |
| `log_folder` | Folder where raster creation logs are written. |
| `value_fields` | List of supported result fields available for raster generation. |
| `omit_value_fields` | List of fields to skip during the current run. |
| `trend_value_field` | Temporary numeric field used for TREND rasterization. |
| `class_value_field` | Temporary numeric field used for CLASS or LABEL rasterization. |
| `nodata_value` | NoData value assigned to missing cells. |
| `run_summary_log` | CSV log summarizing raster creation status. |
| `integer_fields` | Output fields treated as integer rasters. |
| `float_fields` | Output fields treated as floating-point rasters. |
| `class_lookup` | Mapping from class labels to numeric raster codes. |
| `class_labels` | Mapping from numeric class codes to text labels. |
| `trend_labels` | Mapping from trend codes to text labels. |

### Supported Value Fields

| Field | Description |
|---|---|
| `T_NBR` | Number of trend breaks. |
| `T_SEASO` | Trend break season. |
| `T_PERIO` | Trend break period. |
| `T_MAG` | Trend break magnitude. |
| `T_SLOPE` | Trend slope. |
| `PVALUE` | Trend model p-value. |
| `TREND` | Trend direction class. |
| `S_NBR` | Number of seasonal breaks. |
| `S_SEASO` | Seasonal break season. |
| `CLASS` | Numeric change class. |
| `LABEL` | Change class label. |
| `NOBS` | Number of valid observations. |
| `T_CI_LOW` | Trend confidence interval lower bound. |
| `T_CI_EST` | Trend confidence interval estimate. |
| `T_CI_UPP` | Trend confidence interval upper bound. |
| `S_CI_LOW` | Seasonal confidence interval lower bound. |
| `S_CI_EST` | Seasonal confidence interval estimate. |
| `S_CI_UPP` | Seasonal confidence interval upper bound. |

### Process Summary

For each requested value field:

1. Read already processed raster names from the field-specific processed log.
2. Iterate through joined result shapefiles.
3. Skip outputs already listed in the processed log or already present on disk.
4. Validate that the requested field exists.
5. Convert text trend or class fields to numeric values where needed.
6. Convert points to raster using ArcPy `PointToRaster`.
7. Replace null cells with the configured NoData value.
8. Cast integer fields to integer rasters.
9. Build attribute tables and labels for categorical outputs.
10. Append processed logs and run summary records.

### Outputs

| Output | Description |
|---|---|
| `<tile>_<field>.tif` | Tile raster for a specific BFAST output field. |
| `CreateResultRasters_<FIELD>_processed.txt` | Per-field processed raster log. |
| `CreateResultRasters_ALL_OUTPUTS_run_summary.csv` | Summary of created, skipped, and errored outputs. |

### Recommendations

- Use the same `template_raster` for all raster and mosaic operations.
- Use `omit_value_fields` to process only the fields needed for a given analysis.
- Review warnings for unexpected TREND, CLASS, or LABEL values.
- Retain logs to support incremental updates.

---

## 7.5 Build Regional Mosaics

### Script

```text
PythonScript_MosaicResultRasters.py
```

### Purpose

Mosaics tile-level raster outputs into larger regional rasters for each requested BFAST output field. The script supports incremental updates using per-field processed logs.

### User Settings

| Parameter | Description |
|---|---|
| `input_folder` | Folder containing tile raster outputs. |
| `output_folder` | Folder where mosaic rasters are written. |
| `template_raster` | Raster used to define coordinate system and alignment. |
| `value_fields` | List of supported output fields available for mosaicking. |
| `omit_value_fields` | List of fields to skip during the current run. |
| `nodata_value` | NoData value used during cleanup. |
| `integer_fields` | Fields treated as integer rasters. |
| `float_fields` | Fields treated as floating-point rasters. |
| `log_folder` | Folder containing mosaic logs. |
| `run_summary_log` | CSV summary of mosaic creation and updates. |
| `trend_labels` | Trend class labels for raster attribute tables. |
| `class_labels` | Change class labels for raster attribute tables. |

### Process Summary

For each requested value field:

1. Identify tile rasters ending in `_<FIELD>.tif`.
2. Read the field-specific processed log.
3. Identify new tile rasters not already added to the mosaic.
4. Create a new mosaic if one does not exist.
5. Update the existing mosaic if one already exists.
6. Clean NoData values.
7. Build raster attribute tables and labels for categorical outputs.
8. Append the field-specific processed log.
9. Write a mosaic run summary record.

### Outputs

| Output | Description |
|---|---|
| `Mosaic_<FIELD>.tif` | Regional mosaic raster for a selected BFAST field. |
| `Mosaic_<FIELD>_processed.txt` | Per-field record of rasters already included in the mosaic. |
| `MosaicResultRasters_ALL_OUTPUTS_run_summary.csv` | Mosaic run summary log. |

### Recommendations

- Run this after tile-level raster creation.
- Preserve processed logs if using incremental updates.
- Delete or reset processed logs only if intentionally rebuilding mosaics from scratch.
- Verify categorical labels after mosaicking.

---

## 8. Output Field Reference

### Trend and Seasonal Outputs

| Field | Meaning |
|---|---|
| `T_NBR` | Number of detected trend breaks. |
| `T_SEASO` | Season associated with trend break timing. |
| `T_PERIO` | Period associated with trend break timing. |
| `T_MAG` | Magnitude of detected trend change. |
| `T_SLOPE` | Slope of trend component. |
| `PVALUE` | P-value associated with trend model or slope summary. |
| `TREND` | Directional trend class. |
| `S_NBR` | Number of detected seasonal breaks. |
| `S_SEASO` | Season associated with seasonal break timing. |

### Classification Outputs

| Field | Meaning |
|---|---|
| `CLASS` | Numeric class code. |
| `LABEL` | Text label describing the change class. |
| `trend_direction_code` | Numeric direction code for trend behavior. |

### Observation and Confidence Outputs

| Field | Meaning |
|---|---|
| `NOBS` | Number of valid observations. |
| `T_CI_LOW` | Lower bound of trend breakpoint confidence interval. |
| `T_CI_EST` | Estimated trend breakpoint location. |
| `T_CI_UPP` | Upper bound of trend breakpoint confidence interval. |
| `S_CI_LOW` | Lower bound of seasonal breakpoint confidence interval. |
| `S_CI_EST` | Estimated seasonal breakpoint location. |
| `S_CI_UPP` | Upper bound of seasonal breakpoint confidence interval. |

### Classification Labels

The raster creation and mosaicking scripts support class labels including:

| Code | Label |
|---|---|
| 1 | Stable grassland |
| 2 | Interannual climate variability |
| 3 | Abrupt productivity decline |
| 4 | Recovery / resilience |
| 5 | Persistent decline |
| 6 | Persistent improvement |
| 7 | Phenological shift |
| 8 | Highly dynamic / unstable |

---

## 9. Reproducibility and Restart-Safe Design

This workflow is designed for large analyses that may require repeated runs, job recovery, or incremental updates.

### Restart-Safe Features

| Stage | Restart-Safe Mechanism |
|---|---|
| Tile creation | Existing tile shapefiles are skipped. |
| Extraction | Tiles marked `SUCCESS` in `extract_log.csv` are skipped. |
| HPC submission | Jobs are skipped when expected outputs already exist. |
| Result reconstruction | Tiles marked `SUCCESS` in `bfast_results_log.csv` are skipped. |
| Raster creation | Per-field processed logs prevent duplicate raster creation. |
| Mosaicking | Per-field processed logs track rasters already added to mosaics. |

### QA Logs

| Log | Purpose |
|---|---|
| `extract_log.csv` | Tracks tile-level extraction status. |
| `na_fill_log.csv` | Tracks tile-level missing-value filling. |
| `na_fill_pixel_qa_log.csv` | Describes pixel-level NA replacement. |
| `na_fill_summary_qa_log.csv` | Summarizes NA replacement by tile. |
| `bfast_results_log.csv` | Tracks BFAST output reconstruction. |
| `join_results_log.csv` | Tracks shapefile joins and mismatch status. |
| `Fishnet50K_processing_summary.csv` | Master processing summary. |
| `Fishnet50K_processing_progress.csv` | Progress summary. |
| `CreateResultRasters_ALL_OUTPUTS_run_summary.csv` | Raster creation summary. |
| `MosaicResultRasters_ALL_OUTPUTS_run_summary.csv` | Mosaic update summary. |

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
- Confirm filename suffixes match the suffix settings in `RScript_BFASTResults_And_Join_Folder.R`.
- Confirm original tile shapefiles are available for joining.
- Review mismatch CSV files before deleting them.
- Use a consistent `template_raster` for raster creation and mosaicking.

### Common Issues

| Issue | Likely Cause | Suggested Check |
|---|---|---|
| Tile skipped unexpectedly | Log marks it complete or output exists | Review log and output folder. |
| Join mismatch files contain many records | ID mismatch between shapefile and result table | Check `pointid` and `ID` values. |
| Raster field missing | Joined shapefile does not contain requested field | Check `value_fields` and result schema. |
| Mosaic does not update | Processed log already lists rasters | Review or reset `Mosaic_<FIELD>_processed.txt`. |
| HPC job exits early | Missing R package or incorrect path | Check SLURM output and script paths. |

---

## 11. Citation and License Guidance

This workflow relies on the BFAST (Breaks For Additive Season and Trend) framework and associated structural change methodologies for identifying trend and seasonal breakpoints in remote sensing time-series data.

Users should cite the original BFAST publications and related methodological references when using outputs generated by this workflow, along with this repository.

### Core BFAST Methodology

Verbesselt, J., Hyndman, R., Newnham, G., & Culvenor, D. (2010). *Detecting trend and seasonal changes in satellite image time series.* Remote Sensing of Environment, 114(1), 106–115. https://doi.org/10.1016/j.rse.2009.08.014

This publication introduced the BFAST framework and remains the primary methodological reference for trend and seasonal breakpoint detection.

---

### BFAST Monitoring

Verbesselt, J., Zeileis, A., & Herold, M. (2012). *Near real-time disturbance detection using satellite image time series.* Remote Sensing of Environment, 123, 98–108. https://doi.org/10.1016/j.rse.2012.02.022

This publication extends the BFAST framework for monitoring and near real-time disturbance detection.

---

### Structural Change Methodology

Zeileis, A., Leisch, F., Hornik, K., & Kleiber, C. (2002). *strucchange: An R Package for Testing for Structural Change in Linear Regression Models.* Journal of Statistical Software, 7(2), 1–38. https://doi.org/10.18637/jss.v007.i02

The BFAST methodology relies on structural change and breakpoint detection techniques implemented through the strucchange framework. Researchers interested in the statistical foundations of breakpoint estimation and confidence intervals should consult this reference.

---

### BFAST R Package

The workflow uses the R package **bfast** for breakpoint detection and time-series decomposition.

To obtain the appropriate citation for the version of the package used in an analysis, run:

```r
citation("bfast")
```

within R.

### License

For a repository intended to promote reuse and improvements while discouraging privatization of derivative work, the recommended license is:

```text
GNU Affero General Public License v3.0 (AGPL-3.0)
```
