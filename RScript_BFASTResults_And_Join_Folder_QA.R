#--------------------------------------------------------------------------------------
# Name:         RScript_BFASTResults_And_Join_Folder_QA.R
# Author:       Shawn Hutchinson
# Project:      BFAST grassland change analysis, 2001-2025
# Date Created: April 27, 2026
# Last Updated: June 16, 2026
#
# Purpose:
#   Build per-tile BFAST result tables, classify each pixel using the current
#   ecological framework, join results back to centroid shapefiles, and write
#   processing logs that support QA/QC and pixel accounting.
#
# Input folders / files:
#   - BFAST text outputs in input_dir, including trend/season break counts,
#     break timing, break magnitude, confidence intervals, fitted trend output,
#     fitted season output, and NOBS files.
#   - Centroid shapefiles in shape_dir named with shape_prefix + tile + .shp.
#
# Main outputs:
#   - Per-tile result CSVs with suffix result_suffix.
#   - Joined centroid result shapefiles with suffix shape_out_suffix.
#   - Shapefile/result mismatch CSVs for unmatched IDs.
#   - bfast_results_log.csv: tile-level processing summary and class/trend counts.
#   - bfast_trend_cumulative_totals.csv: cumulative trend summary.
#   - bfast_join_summary_log.csv: shapefile join accounting.
#   - pixel_accounting_log.csv: master tile-level accounting log for tracking
#     where pixels are retained, flagged, or lost across processing stages.
#   - dropped_pixel_reason_log.csv: per-pixel reason log for missing,
#     unmatched, trend-warning, interpolation-QA, or catch-all Class 11 pixels.
#
# Classification / trend metadata:
#   - TREND values: Negative, Stable, Positive.
#   - trend_direction_code values: -1 = Negative, 0 = Stable, 1 = Positive,
#     -9999 = missing/NoData.
#   - Trend regression warnings, including essentially perfect fit warnings, are
#     retained as QA metadata but do not create a separate trend class. Pixels
#     with trend warnings are classified as Negative, Stable, or Positive using
#     the calculated slope and p-value when available.
#   - Ecological classes:
#       1  Stable grassland
#       2  Climate-driven variability
#       3  Abrupt decline
#       4  Recovery trajectory
#       5  Sustained degradation
#       6  Sustained improvement
#       7  Phenological shift
#       8  Highly dynamic
#       9  Gradual decline
#       10 Gradual improvement
#       11 Other, for valid BFAST combinations not otherwise captured
#   - Missing core classification outputs use missing_output_value, currently -9999.
#   - Optional pixel-level fill QA adds interpolation metrics and classes.
#     Excessive and severe interpolation are tracked separately from trend
#     warnings and can be mapped as INTERP_PCT and INTERP_CLASS outputs.
#
# QA/QC notes:
#   - Input files are matched by ID rather than row order to reduce silent joins.
#   - Duplicate IDs / pointids are checked before joins.
#   - Missing trend inputs are tallied separately from missing class/label inputs.
#   - Tiles already marked SUCCESS in bfast_results_log.csv are skipped.
#   - ESRI Shapefile field names are limited by the driver; full QA/QC details are
#     retained in CSV/log outputs rather than added as extra shapefile attributes.
#
# Required R packages: data.table, broom, dplyr, sf
#--------------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(data.table)
  library(broom)
  library(dplyr)
  library(sf)
})

#==============================#
# User settings
#==============================#

input_dir <- "D:/Research/Projects/BFAST_2001_2025/BFAST_H0.15/extract"
result_output_dir <- "D:/Research/Projects/BFAST_2001_2025/BFAST_H0.15_Test/results"
shape_dir <- "D:/Research/Projects/BFAST_2001_2025/BFAST/tiles"
join_output_dir <- "D:/Research/Projects/BFAST_2001_2025/BFAST_H0.15_Test/tile_results"
log_dir <- "D:/Research/Projects/BFAST_2001_2025/BFAST_H0.15_Test/logs"

suffix_nobs <- "_nobs.txt"
#suffix_residuals_bfast <- "_residuals_bfast.txt"
suffix_season_bfast     <- "_season_bfast.txt"
suffix_season_confint   <- "_season_breaks_confint.txt"
suffix_season_breaktime <- "_season_breaks_time.txt"
suffix_season_nbbreaks  <- "_season_nbbreaks.txt"
suffix_trend_bfast     <- "_trend_bfast.txt"
suffix_trend_confint   <- "_trend_breaks_confint.txt"
suffix_trend_breakmag  <- "_trend_breaks_magnitude.txt"
suffix_trend_breaktime <- "_trend_breaks_time.txt"
suffix_trend_nbbreaks  <- "_trend_nbbreaks.txt"

result_suffix    <- "_results.csv"

shape_prefix <- "Centroids_"
shape_out_suffix <- "_Result.shp"
shape_mismatch_suffix <- "_shape_unmatched.csv"
result_mismatch_suffix <- "_result_unmatched.csv"

periods_per_season <- 23
pvalue_threshold <- 0.05

# BFAST classification settings. These are copied from the draft classifier script
# and applied directly to each tile results CSV.
alpha <- 0.05
small_magnitude_threshold <- 0.03
large_magnitude_threshold <- 0.07
# Recovery/resilience proxy: current inputs do not include full directional
# break sequences, so class 4 is assigned only when the largest trend break is
# negative, the overall post-series tendency is positive, and at least two
# trend breaks are present. Set recovery_require_significant_slope <- TRUE to
# require the overall positive slope p-value to pass alpha.
recovery_magnitude_threshold <- small_magnitude_threshold
recovery_slope_threshold <- 0
recovery_require_significant_slope <- TRUE
high_break_count <- 4
missing_output_value <- -9999

# Optional interpolation QA screen. The pixel-level fill QA file should come from
# RScript_ExtractAndFill_Folder_with_QA.r and contain tile, pointid, and one or
# more fill metrics such as n_na_filled / fill_count, pct_missing_before / fill_pct,
# and max_na_gap / max_gap.
#
# Recommended current behavior based on diagnostic results:
#   - Do not create a separate Indeterminate trend class. Trend warnings are
#     retained as QA metadata while pixels are classified as Negative, Stable,
#     or Positive when slope and p-value are available.
#   - Track excessive and severe interpolation separately from trend warnings.
#   - If exclude_excessively_interpolated_from_classification is TRUE, pixels that
#     exceed either threshold below are retained in result CSVs but CLASS/LABEL are
#     set to missing_output_value / NA.
fill_pixel_qa_log_file <- file.path(log_dir, "na_fill_pixel_qa_log.csv")
use_fill_interpolation_qa <- file.exists(fill_pixel_qa_log_file)
exclude_excessively_interpolated_from_classification <- FALSE
fill_pct_moderate_threshold <- 0.05
fill_pct_excessive_threshold <- 0.20
fill_pct_severe_threshold <- 0.50
max_gap_moderate_threshold <- 5
max_gap_excessive_threshold <- 20
max_gap_severe_threshold <- 50

process_log_file <- file.path(log_dir, "bfast_results_log.csv")
trend_cumulative_file <- file.path(log_dir, "bfast_trend_cumulative.csv")
join_summary_log_file <- file.path(log_dir, "join_results_log.csv")

# Cross-stage QA/QC logs.
# pixel_accounting_log.csv is one row per tile and is designed to trace where
# pixels are retained, flagged, or lost from result construction through joining.
# dropped_pixel_reason_log.csv is one row per tile/pixel/reason for pixels with
# missing inputs, trend warnings, interpolation-QA flags, Class 11 Other assignments, or
# shapefile/result join mismatches.
pixel_accounting_log_file <- file.path(log_dir, "pixel_accounting_log.csv")
dropped_pixel_reason_log_file <- file.path(log_dir, "dropped_pixel_reason_log.csv")

#==============================#
# Helper functions
#==============================#

stop_if_missing <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("Required file not found: %s", path), call. = FALSE)
  }
}


# Delete all sidecar files for an existing ESRI Shapefile before writing a new one.
# This avoids schema-update errors when a previous failed run left behind a partial
# or incompatible shapefile. The original input shapefile is not touched; this is
# only called on the output shapefile path.
delete_existing_shapefile <- function(shp_path) {
  base <- tools::file_path_sans_ext(shp_path)
  sidecars <- paste0(
    base,
    c(
      ".shp", ".shx", ".dbf", ".prj", ".cpg", ".qpj",
      ".sbn", ".sbx", ".fbn", ".fbx", ".ain", ".aih",
      ".ixs", ".mxs", ".atx", ".xml"
    )
  )
  existing <- sidecars[file.exists(sidecars)]
  if (length(existing) > 0) {
    unlink(existing, force = TRUE)
  }
  invisible(existing)
}


# Count helper functions used by the QA/QC log.
# These operate on a vector directly, which avoids errors from passing
# precomputed columns rather than data-frame/field-name pairs.
is_missing_value <- function(x, missing_value = missing_output_value) {
  if (is.factor(x)) x <- as.character(x)

  if (is.numeric(x) || is.integer(x)) {
    return(is.na(x) | x == missing_value)
  }

  x_chr <- trimws(as.character(x))
  is.na(x_chr) | x_chr == "" | x_chr == as.character(missing_value)
}

count_missing_field <- function(x, missing_value = missing_output_value) {
  sum(is_missing_value(x, missing_value), na.rm = TRUE)
}

count_valid_field <- function(x, missing_value = missing_output_value) {
  length(x) - count_missing_field(x, missing_value)
}

count_true <- function(x) {
  sum(isTRUE(x) | (!is.na(x) & x), na.rm = TRUE)
}

mass_balance_ok <- function(total_count, valid_count, missing_count) {
  isTRUE(as.integer(total_count) == as.integer(valid_count) + as.integer(missing_count))
}


safe_log_value <- function(df, col_name, default = NA) {
  if (is.null(df) || !(col_name %in% names(df)) || nrow(df) == 0) {
    return(default)
  }
  df[[col_name]][1]
}


normalize_names <- function(df) {
  names(df) <- tolower(names(df))
  df
}

coerce_join_id <- function(x) {
  x <- trimws(as.character(x))
  x <- sub("\\.0$", "", x)
  x
}

find_first_column <- function(df, candidates) {
  nms <- names(df)
  idx <- match(tolower(candidates), tolower(nms), nomatch = 0)
  idx <- idx[idx > 0]
  if (length(idx) == 0) return(NA_character_)
  nms[idx[1]]
}

read_fill_qa_for_tile <- function(tile,
                                  fill_pixel_qa_log_file,
                                  fill_pct_moderate_threshold,
                                  fill_pct_excessive_threshold,
                                  fill_pct_severe_threshold,
                                  max_gap_moderate_threshold,
                                  max_gap_excessive_threshold,
                                  max_gap_severe_threshold) {
  if (is.null(fill_pixel_qa_log_file) || !file.exists(fill_pixel_qa_log_file)) {
    return(NULL)
  }

  qa <- tryCatch(
    data.table::fread(fill_pixel_qa_log_file, showProgress = FALSE),
    error = function(e) NULL
  )

  if (is.null(qa) || nrow(qa) == 0) {
    return(NULL)
  }

  qa <- as.data.frame(normalize_names(qa))

  tile_col <- find_first_column(qa, c("tile", "tile_id", "tileid", "file_tile"))
  id_col <- find_first_column(qa, c("pointid", "point_id", "id", "pixelid", "pixel_id", "poly_id"))

  if (is.na(id_col)) {
    warning("Fill QA file was found, but no point ID column was recognized. Skipping fill QA join.")
    return(NULL)
  }

  if (is.na(tile_col)) {
    # Fall back to tile-independent matching only if the file has no tile field.
    qa$tile <- as.character(tile)
  } else {
    names(qa)[names(qa) == tile_col] <- "tile"
    qa$tile <- as.character(qa$tile)
    qa <- qa[qa$tile == as.character(tile), , drop = FALSE]
  }

  names(qa)[names(qa) == id_col] <- "pointid"
  qa$pointid <- coerce_join_id(qa$pointid)

  fill_count_col <- find_first_column(qa, c("n_na_filled", "na_filled", "fill_count", "filled_count", "total_filled"))
  fill_pct_col <- find_first_column(qa, c("fill_pct", "pct_filled", "pct_missing_before", "pct_na_before", "percent_missing_before"))
  max_gap_col <- find_first_column(qa, c("max_na_gap", "max_gap", "max_gap_length", "longest_gap"))

  qa_out <- data.frame(
    ID = suppressWarnings(as.numeric(qa$pointid)),
    fill_qa_matched = TRUE,
    fill_count = if (!is.na(fill_count_col)) suppressWarnings(as.numeric(qa[[fill_count_col]])) else NA_real_,
    fill_pct = if (!is.na(fill_pct_col)) suppressWarnings(as.numeric(qa[[fill_pct_col]])) else NA_real_,
    max_gap = if (!is.na(max_gap_col)) suppressWarnings(as.numeric(qa[[max_gap_col]])) else NA_real_,
    stringsAsFactors = FALSE
  )

  # Accept either fractional percentages (0.20) or 0-100 percentages (20).
  if (any(qa_out$fill_pct > 1, na.rm = TRUE)) {
    qa_out$fill_pct <- qa_out$fill_pct / 100
  }

  qa_out$moderate_interpolation <- (!is.na(qa_out$fill_pct) & qa_out$fill_pct >= fill_pct_moderate_threshold) |
    (!is.na(qa_out$max_gap) & qa_out$max_gap >= max_gap_moderate_threshold)

  qa_out$excessive_interpolation <- (!is.na(qa_out$fill_pct) & qa_out$fill_pct >= fill_pct_excessive_threshold) |
    (!is.na(qa_out$max_gap) & qa_out$max_gap >= max_gap_excessive_threshold)

  qa_out$severe_interpolation <- (!is.na(qa_out$fill_pct) & qa_out$fill_pct >= fill_pct_severe_threshold) |
    (!is.na(qa_out$max_gap) & qa_out$max_gap >= max_gap_severe_threshold)

  qa_out$INTERP_CLASS <- dplyr::case_when(
    qa_out$severe_interpolation ~ 4,
    qa_out$excessive_interpolation ~ 3,
    qa_out$moderate_interpolation ~ 2,
    !is.na(qa_out$fill_count) & qa_out$fill_count > 0 ~ 1,
    TRUE ~ 0
  )

  qa_out$INTERP_LABEL <- dplyr::case_when(
    qa_out$INTERP_CLASS == 4 ~ "Severe interpolation",
    qa_out$INTERP_CLASS == 3 ~ "Excessive interpolation",
    qa_out$INTERP_CLASS == 2 ~ "Moderate interpolation",
    qa_out$INTERP_CLASS == 1 ~ "Minor interpolation",
    qa_out$INTERP_CLASS == 0 ~ "No interpolation",
    TRUE ~ NA_character_
  )

  qa_out$INTERP_PCT <- qa_out$fill_pct

  qa_out <- qa_out[!is.na(qa_out$ID), , drop = FALSE]
  qa_out <- qa_out[!duplicated(qa_out$ID), , drop = FALSE]
  qa_out
}

make_pixel_accounting_row <- function(tile, process_log_row = NULL, join_log_row = NULL) {
  result_rows <- safe_log_value(process_log_row, "n_rows", NA_integer_)
  shape_pixels <- safe_log_value(join_log_row, "n_shape_features", NA_integer_)
  result_join_rows <- safe_log_value(join_log_row, "n_result_rows", result_rows)
  shape_unmatched <- safe_log_value(join_log_row, "n_shape_unmatched", NA_integer_)
  result_unmatched <- safe_log_value(join_log_row, "n_result_unmatched", NA_integer_)
  shape_matched <- safe_log_value(join_log_row, "n_shape_matched", NA_integer_)
  result_matched <- safe_log_value(join_log_row, "n_result_matched", NA_integer_)

  data.frame(
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    tile = tile,
    # Counts from result construction / classification
    result_rows = result_rows,
    valid_nobs = safe_log_value(process_log_row, "valid_nobs_count", NA_integer_),
    missing_nobs = safe_log_value(process_log_row, "missing_nobs_count", NA_integer_),
    valid_trend_inputs = safe_log_value(process_log_row, "valid_trend_input_count", NA_integer_),
    missing_trend_inputs = safe_log_value(process_log_row, "missing_trend_input_count", NA_integer_),
    missing_trend_pvalue = safe_log_value(process_log_row, "missing_trend_pvalue_count", NA_integer_),
    missing_trend_slope = safe_log_value(process_log_row, "missing_trend_slope_count", NA_integer_),
    valid_trend_outputs = safe_log_value(process_log_row, "valid_trend_output_count", NA_integer_),
    missing_trend_outputs = safe_log_value(process_log_row, "missing_trend_output_count", NA_integer_),
    valid_trend_codes = safe_log_value(process_log_row, "valid_trend_code_count", NA_integer_),
    missing_trend_codes = safe_log_value(process_log_row, "missing_trend_code_count", NA_integer_),
    indeterminate_trend = 0,
    perfect_fit_warnings = safe_log_value(process_log_row, "perfect_fit_warning_count", NA_integer_),
    trend_warnings = safe_log_value(process_log_row, "trend_warning_count", NA_integer_),
    fill_qa_matched = safe_log_value(process_log_row, "fill_qa_matched_count", NA_integer_),
    excessive_interpolation = safe_log_value(process_log_row, "excessive_interpolation_count", NA_integer_),
    severe_interpolation = safe_log_value(process_log_row, "severe_interpolation_count", NA_integer_),
    excessive_interpolation_excluded = safe_log_value(process_log_row, "excessive_interpolation_excluded_count", NA_integer_),
    valid_label_inputs = safe_log_value(process_log_row, "valid_label_input_count", NA_integer_),
    missing_label_inputs = safe_log_value(process_log_row, "missing_label_input_count", NA_integer_),
    valid_class = safe_log_value(process_log_row, "valid_class_count", NA_integer_),
    missing_class = safe_log_value(process_log_row, "missing_class_count", NA_integer_),
    valid_label = safe_log_value(process_log_row, "valid_label_count", NA_integer_),
    missing_label = safe_log_value(process_log_row, "missing_label_count", NA_integer_),
    class_11_other = safe_log_value(process_log_row, "other_count", NA_integer_),
    # Counts from shapefile/result joining
    shape_pixels = shape_pixels,
    result_join_rows = result_join_rows,
    shape_matched = shape_matched,
    result_matched = result_matched,
    shape_not_in_results = shape_unmatched,
    results_not_in_shape = result_unmatched,
    join_output_status = safe_log_value(join_log_row, "status", NA_character_),
    # QA checks
    result_row_balance_ok = mass_balance_ok(
      result_rows,
      safe_log_value(process_log_row, "valid_nobs_count", NA_integer_),
      safe_log_value(process_log_row, "missing_nobs_count", NA_integer_)
    ),
    trend_code_balance_ok = safe_log_value(process_log_row, "trend_mass_balance_ok", NA),
    class_balance_ok = safe_log_value(process_log_row, "class_mass_balance_ok", NA),
    label_balance_ok = safe_log_value(process_log_row, "label_mass_balance_ok", NA),
    join_shape_balance_ok = mass_balance_ok(shape_pixels, shape_matched, shape_unmatched),
    join_result_balance_ok = mass_balance_ok(result_join_rows, result_matched, result_unmatched),
    status = ifelse(
      identical(safe_log_value(process_log_row, "status", NA_character_), "SUCCESS") &&
        identical(safe_log_value(join_log_row, "status", NA_character_), "SUCCESS"),
      "SUCCESS",
      "CHECK"
    ),
    message = paste(
      na.omit(c(
        safe_log_value(process_log_row, "message", NA_character_),
        safe_log_value(join_log_row, "message", NA_character_)
      )),
      collapse = " | "
    ),
    stringsAsFactors = FALSE
  )
}

make_dropped_pixel_reason_log <- function(tile,
                                          result_df = NULL,
                                          shape_mismatch_file = NULL,
                                          result_mismatch_file = NULL) {
  reason_rows <- list()

  add_reason_rows <- function(df, idx, stage, reason) {
    if (is.null(df) || length(idx) == 0 || !any(idx, na.rm = TRUE)) {
      return(NULL)
    }

    keep <- which(idx)
    out <- data.frame(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      tile = tile,
      pointid = if ("ID" %in% names(df)) df$ID[keep] else NA,
      stage = stage,
      reason = reason,
      NOBS = if ("NOBS" %in% names(df)) df$NOBS[keep] else NA,
      T_NBR = if ("T_NBR" %in% names(df)) df$T_NBR[keep] else NA,
      S_NBR = if ("S_NBR" %in% names(df)) df$S_NBR[keep] else NA,
      PVALUE = if ("PVALUE" %in% names(df)) df$PVALUE[keep] else NA,
      T_SLOPE = if ("T_SLOPE" %in% names(df)) df$T_SLOPE[keep] else NA,
      TREND = if ("TREND" %in% names(df)) df$TREND[keep] else NA,
      trend_direction_code = if ("trend_direction_code" %in% names(df)) df$trend_direction_code[keep] else NA,
      CLASS = if ("CLASS" %in% names(df)) df$CLASS[keep] else NA,
      LABEL = if ("LABEL" %in% names(df)) df$LABEL[keep] else NA,
      TREND_WARN = if ("TREND_WARN" %in% names(df)) df$TREND_WARN[keep] else NA,
      fill_count = if ("fill_count" %in% names(df)) df$fill_count[keep] else NA,
      fill_pct = if ("fill_pct" %in% names(df)) df$fill_pct[keep] else NA,
      max_gap = if ("max_gap" %in% names(df)) df$max_gap[keep] else NA,
      excessive_interpolation = if ("excessive_interpolation" %in% names(df)) df$excessive_interpolation[keep] else NA,
      severe_interpolation = if ("severe_interpolation" %in% names(df)) df$severe_interpolation[keep] else NA,
      INTERP_PCT = if ("INTERP_PCT" %in% names(df)) df$INTERP_PCT[keep] else NA,
      INTERP_CLASS = if ("INTERP_CLASS" %in% names(df)) df$INTERP_CLASS[keep] else NA,
      stringsAsFactors = FALSE
    )
    out
  }

  if (!is.null(result_df) && nrow(result_df) > 0) {
    result_df <- as.data.frame(result_df)
    reason_rows[[length(reason_rows) + 1]] <- add_reason_rows(
      result_df,
      is_missing_value(result_df$NOBS),
      "CLASSIFICATION",
      "MISSING_NOBS"
    )
    reason_rows[[length(reason_rows) + 1]] <- add_reason_rows(
      result_df,
      is_missing_value(result_df$PVALUE),
      "TREND",
      "MISSING_PVALUE"
    )
    reason_rows[[length(reason_rows) + 1]] <- add_reason_rows(
      result_df,
      is_missing_value(result_df$T_SLOPE),
      "TREND",
      "MISSING_T_SLOPE"
    )
    reason_rows[[length(reason_rows) + 1]] <- add_reason_rows(
      result_df,
      is_missing_value(result_df$T_NBR),
      "CLASSIFICATION",
      "MISSING_T_NBR"
    )
    reason_rows[[length(reason_rows) + 1]] <- add_reason_rows(
      result_df,
      is_missing_value(result_df$S_NBR),
      "CLASSIFICATION",
      "MISSING_S_NBR"
    )
    reason_rows[[length(reason_rows) + 1]] <- add_reason_rows(
      result_df,
      is.na(result_df$TREND) | trimws(as.character(result_df$TREND)) == "",
      "TREND",
      "MISSING_TREND"
    )
    reason_rows[[length(reason_rows) + 1]] <- add_reason_rows(
      result_df,
      !is.na(result_df$TREND_WARN) & trimws(as.character(result_df$TREND_WARN)) != "",
      "TREND",
      "TREND_WARNING"
    )
    reason_rows[[length(reason_rows) + 1]] <- add_reason_rows(
      result_df,
      is_missing_value(result_df$CLASS),
      "CLASSIFICATION",
      "MISSING_CLASS"
    )
    reason_rows[[length(reason_rows) + 1]] <- add_reason_rows(
      result_df,
      is.na(result_df$LABEL) | trimws(as.character(result_df$LABEL)) == "",
      "CLASSIFICATION",
      "MISSING_LABEL"
    )
    if ("excessive_interpolation" %in% names(result_df)) {
      reason_rows[[length(reason_rows) + 1]] <- add_reason_rows(
        result_df,
        result_df$excessive_interpolation,
        "FILL_QA",
        "EXCESSIVE_INTERPOLATION"
      )
    }
    if ("severe_interpolation" %in% names(result_df)) {
      reason_rows[[length(reason_rows) + 1]] <- add_reason_rows(
        result_df,
        result_df$severe_interpolation,
        "FILL_QA",
        "SEVERE_INTERPOLATION"
      )
    }
    reason_rows[[length(reason_rows) + 1]] <- add_reason_rows(
      result_df,
      result_df$CLASS == 11,
      "CLASSIFICATION",
      "CLASS_11_OTHER"
    )
  }

  if (!is.null(shape_mismatch_file) && file.exists(shape_mismatch_file)) {
    shp_unmatched <- tryCatch(utils::read.csv(shape_mismatch_file, stringsAsFactors = FALSE), error = function(e) NULL)
    if (!is.null(shp_unmatched) && nrow(shp_unmatched) > 0) {
      reason_rows[[length(reason_rows) + 1]] <- data.frame(
        timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        tile = tile,
        pointid = if ("pointid" %in% names(shp_unmatched)) shp_unmatched$pointid else NA,
        stage = "JOIN",
        reason = "SHAPE_NOT_IN_RESULTS",
        NOBS = NA, T_NBR = NA, S_NBR = NA, PVALUE = NA, T_SLOPE = NA,
        TREND = NA, trend_direction_code = NA, CLASS = NA, LABEL = NA, TREND_WARN = NA,
        fill_count = NA, fill_pct = NA, max_gap = NA, excessive_interpolation = NA, severe_interpolation = NA,
        INTERP_PCT = NA, INTERP_CLASS = NA,
        stringsAsFactors = FALSE
      )
    }
  }

  if (!is.null(result_mismatch_file) && file.exists(result_mismatch_file)) {
    result_unmatched <- tryCatch(utils::read.csv(result_mismatch_file, stringsAsFactors = FALSE), error = function(e) NULL)
    if (!is.null(result_unmatched) && nrow(result_unmatched) > 0) {
      reason_rows[[length(reason_rows) + 1]] <- data.frame(
        timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        tile = tile,
        pointid = if ("ID" %in% names(result_unmatched)) result_unmatched$ID else NA,
        stage = "JOIN",
        reason = "RESULT_NOT_IN_SHAPE",
        NOBS = if ("NOBS" %in% names(result_unmatched)) result_unmatched$NOBS else NA,
        T_NBR = if ("T_NBR" %in% names(result_unmatched)) result_unmatched$T_NBR else NA,
        S_NBR = if ("S_NBR" %in% names(result_unmatched)) result_unmatched$S_NBR else NA,
        PVALUE = if ("PVALUE" %in% names(result_unmatched)) result_unmatched$PVALUE else NA,
        T_SLOPE = if ("T_SLOPE" %in% names(result_unmatched)) result_unmatched$T_SLOPE else NA,
        TREND = if ("TREND" %in% names(result_unmatched)) result_unmatched$TREND else NA,
        trend_direction_code = if ("trend_direction_code" %in% names(result_unmatched)) result_unmatched$trend_direction_code else NA,
        CLASS = if ("CLASS" %in% names(result_unmatched)) result_unmatched$CLASS else NA,
        LABEL = if ("LABEL" %in% names(result_unmatched)) result_unmatched$LABEL else NA,
        TREND_WARN = if ("TREND_WARN" %in% names(result_unmatched)) result_unmatched$TREND_WARN else NA,
        stringsAsFactors = FALSE
      )
    }
  }

  reason_rows <- reason_rows[!vapply(reason_rows, is.null, logical(1))]
  if (length(reason_rows) == 0) {
    return(data.frame())
  }

  dplyr::bind_rows(reason_rows)
}

check_unique_key <- function(df, key_name, df_name) {
  if (!(key_name %in% names(df))) {
    stop(sprintf("Column '%s' not found in %s.", key_name, df_name), call. = FALSE)
  }

  if (anyDuplicated(df[[key_name]]) > 0) {
    dup_val <- unique(df[[key_name]][duplicated(df[[key_name]])])[1]
    stop(
      sprintf(
        "Duplicate key values found in %s for '%s'. Example duplicate: %s",
        df_name, key_name, dup_val
      ),
      call. = FALSE
    )
  }
}

append_csv <- function(new_df, csv_file) {
  if (file.exists(csv_file)) {
    existing_df <- tryCatch(
      utils::read.csv(csv_file, stringsAsFactors = FALSE),
      error = function(e) NULL
    )

    if (!is.null(existing_df)) {
      missing_cols <- setdiff(names(new_df), names(existing_df))
      for (col in missing_cols) existing_df[[col]] <- NA

      extra_cols <- setdiff(names(existing_df), names(new_df))
      for (col in extra_cols) new_df[[col]] <- NA

      new_df <- new_df[, names(existing_df), drop = FALSE]
      combined_df <- rbind(existing_df, new_df)
    } else {
      combined_df <- new_df
    }
  } else {
    combined_df <- new_df
  }

  utils::write.csv(combined_df, csv_file, row.names = FALSE)
}

get_completed_tiles <- function(process_log_file) {
  if (!file.exists(process_log_file)) {
    return(character(0))
  }

  log_df <- tryCatch(
    utils::read.csv(process_log_file, stringsAsFactors = FALSE),
    error = function(e) NULL
  )

  if (is.null(log_df) || nrow(log_df) == 0) {
    return(character(0))
  }

  if (!all(c("tile", "status") %in% names(log_df))) {
    warning("bfast_results_log.csv does not contain both 'tile' and 'status'. No tiles will be skipped.")
    return(character(0))
  }

  unique(as.character(log_df$tile[log_df$status == "SUCCESS"]))
}

get_tiles_with_complete_bfast_outputs <- function(input_dir,
                                                  suffix_trend_nbbreaks,
                                                  suffix_trend_breaktime,
                                                  suffix_trend_breakmag,
                                                  suffix_trend_bfast,
                                                  suffix_trend_confint,
                                                  suffix_season_nbbreaks,
                                                  suffix_season_breaktime,
                                                  suffix_season_bfast,
                                                  suffix_season_confint,
                                                  suffix_nobs) {
  all_files <- list.files(input_dir, full.names = FALSE)

  required_suffixes <- c(
    suffix_trend_nbbreaks,
    suffix_trend_breaktime,
    suffix_trend_breakmag,
    suffix_trend_bfast,
    suffix_trend_confint,
    suffix_season_nbbreaks,
    suffix_season_breaktime,
    suffix_season_bfast,
    suffix_season_confint,
    suffix_nobs
  )

  pattern <- paste0("(", paste0(required_suffixes, collapse = "|"), ")$")

  matching_files <- all_files[grepl(pattern, all_files)]
  tile_candidates <- unique(sub(pattern, "", matching_files))

  complete_tiles <- tile_candidates[
    file.exists(file.path(input_dir, paste0(tile_candidates, suffix_trend_nbbreaks))) &
      file.exists(file.path(input_dir, paste0(tile_candidates, suffix_trend_breaktime))) &
      file.exists(file.path(input_dir, paste0(tile_candidates, suffix_trend_breakmag))) &
      file.exists(file.path(input_dir, paste0(tile_candidates, suffix_trend_bfast))) &
      file.exists(file.path(input_dir, paste0(tile_candidates, suffix_trend_confint))) &
      file.exists(file.path(input_dir, paste0(tile_candidates, suffix_season_nbbreaks))) &
      file.exists(file.path(input_dir, paste0(tile_candidates, suffix_season_breaktime))) &
      file.exists(file.path(input_dir, paste0(tile_candidates, suffix_season_bfast))) &
      file.exists(file.path(input_dir, paste0(tile_candidates, suffix_season_confint))) &
      file.exists(file.path(input_dir, paste0(tile_candidates, suffix_nobs)))
  ]

  complete_tiles <- unique(as.character(complete_tiles))
  complete_tiles[order(as.numeric(complete_tiles))]
}

read_two_column_file <- function(path, col_names) {
  dt <- data.table::fread(path, header = FALSE)

  if (ncol(dt) < 2) {
    stop(sprintf("Expected at least 2 columns in file: %s", path), call. = FALSE)
  }

  dt <- dt[, 1:2]
  data.table::setnames(dt, names(dt), col_names)
  as.data.frame(dt)
}

read_confint_file <- function(path, col_names) {
  dt <- data.table::fread(path, header = FALSE, fill = TRUE)

  if (ncol(dt) < 2) {
    stop(sprintf("Expected an ID column and at least one confidence-interval column in file: %s", path), call. = FALSE)
  }

  ids <- dt[[1]]
  value_dt <- dt[, -1, with = FALSE]

  # Confidence interval files may contain more than three columns if multiple
  # breaks are written. The joined shapefile keeps the first interval only:
  # lower bound, estimated breakpoint, and upper bound.
  for (i in seq_along(value_dt)) {
    value_dt[[i]] <- suppressWarnings(as.numeric(value_dt[[i]]))
  }

  while (ncol(value_dt) < 3) {
    value_dt[[paste0("missing_", ncol(value_dt) + 1)]] <- NA_real_
  }

  out <- data.frame(
    ID = ids,
    value_dt[[1]],
    value_dt[[2]],
    value_dt[[3]],
    stringsAsFactors = FALSE
  )

  names(out) <- col_names
  out
}

compute_trend_break_timing <- function(time_df, periods_per_season) {
  time_df %>%
    dplyr::mutate(
      T_SEASON = ifelse(is.na(Time), NA_real_, trunc(Time / periods_per_season)),
      T_PERIOD = ifelse(is.na(Time), NA_real_, Time - T_SEASON * periods_per_season)
    ) %>%
    dplyr::select(ID, T_SEASON, T_PERIOD)
}

compute_season_break_timing <- function(time_df, periods_per_season) {
  time_df %>%
    dplyr::mutate(
      S_SEASON = ifelse(is.na(Time), NA_real_, trunc(Time / periods_per_season))
    ) %>%
    dplyr::select(ID, S_SEASON)
}

adjust_trend_break_count <- function(df) {
  df %>%
    dplyr::mutate(
      T_PERIOD = ifelse(is.na(T_PERIOD), 0, T_PERIOD),
      T_SEASON = ifelse(is.na(T_SEASON), 0, T_SEASON),
      T_NBR = T_NBR - ifelse(T_SEASON == 0, 1, 0)
    )
}

adjust_season_break_count <- function(df) {
  df %>%
    dplyr::mutate(
      S_SEASON = ifelse(is.na(S_SEASON), 0, S_SEASON),
      S_NBR = S_NBR - ifelse(S_SEASON == 0, 1, 0)
    )
}

compute_trend_stats <- function(path, pvalue_threshold) {
  trend_raw <- data.table::fread(path, header = FALSE, fill = TRUE)

  if (ncol(trend_raw) < 2) {
    stop(sprintf("Trend file must contain an ID column and at least one time column: %s", path), call. = FALSE)
  }

  ids <- trend_raw[[1]]
  trend_matrix <- as.matrix(trend_raw[, -1, with = FALSE])
  storage.mode(trend_matrix) <- "numeric"

  n_time <- ncol(trend_matrix)
  if (n_time < 2) {
    stop(sprintf("Trend file must contain at least 2 time points: %s", path), call. = FALSE)
  }

  # The previous version used one matrix-response lm():
  #   lm(t(trend_matrix) ~ xdata)
  # That fails with "0 (non-NA) cases" when robust BFAST output contains
  # rows with all-NA trend values, or when NA patterns across rows remove all
  # complete time steps. Fit each ID independently instead.
  slope_values <- rep(NA_real_, length(ids))
  pvalue_values <- rep(NA_real_, length(ids))
  trend_warning_values <- rep(NA_character_, length(ids))
  trend_indeterminate <- rep(FALSE, length(ids))

  for (i in seq_along(ids)) {
    y <- as.numeric(trend_matrix[i, ])
    x <- seq_along(y)
    keep <- is.finite(x) & is.finite(y)

    # Need at least two valid points and some variation in x/y to estimate slope.
    if (sum(keep) >= 2 && length(unique(y[keep])) > 1) {
      fit <- tryCatch(
        stats::lm(y[keep] ~ x[keep]),
        error = function(e) NULL
      )

      if (!is.null(fit)) {
        perfect_fit_warning <- FALSE
        warning_messages <- character(0)

        coef_table <- tryCatch(
          withCallingHandlers(
            summary(fit)$coefficients,
            warning = function(w) {
              warning_messages <<- c(warning_messages, conditionMessage(w))
              if (grepl("essentially perfect fit", conditionMessage(w), ignore.case = TRUE)) {
                perfect_fit_warning <<- TRUE
              }
              invokeRestart("muffleWarning")
            }
          ),
          error = function(e) NULL
        )

        if (length(warning_messages) > 0) {
          trend_warning_values[i] <- paste(unique(warning_messages), collapse = " | ")
        }

        if (perfect_fit_warning) {
          # Keep the warning as QA metadata, but do not create a separate
          # separate trend class. Use the available slope and p-value when
          # summary.lm returns them so the pixel can be assigned Negative,
          # Stable, or Positive consistently with the rest of the analysis.
          trend_indeterminate[i] <- FALSE
        }

        if (!is.null(coef_table) && nrow(coef_table) >= 2) {
          slope_values[i] <- coef_table[2, "Estimate"]
          pvalue_values[i] <- coef_table[2, "Pr(>|t|)"]
        }
      }
    } else if (sum(keep) >= 2 && length(unique(y[keep])) == 1) {
      # Constant fitted trend: slope is zero and should classify as stable.
      slope_values[i] <- 0
      pvalue_values[i] <- 1
    }
  }

  data.frame(
    ID = ids,
    T_SLOPE = slope_values,
    PVALUE = pvalue_values,
    TREND_WARN = trend_warning_values,
    TREND_INDET = trend_indeterminate,
    stringsAsFactors = FALSE
  ) %>%
    dplyr::mutate(
      TREND = dplyr::case_when(
        is.na(PVALUE) | is.na(T_SLOPE) ~ NA_character_,
        PVALUE >= pvalue_threshold     ~ "Stable",
        T_SLOPE > 0                    ~ "Positive",
        T_SLOPE < 0                    ~ "Negative",
        TRUE                           ~ "Stable"
      )
    )
}

classify_bfast_results <- function(df,
                                   alpha,
                                   small_magnitude_threshold,
                                   large_magnitude_threshold,
                                   recovery_magnitude_threshold,
                                   recovery_slope_threshold,
                                   recovery_require_significant_slope,
                                   high_break_count,
                                   missing_output_value = -9999,
                                   exclude_excessively_interpolated_from_classification = TRUE) {
  missing_output_value <- as.numeric(missing_output_value)

  df %>%
    dplyr::mutate(
      ID = as.numeric(ID),
      T_NBR = as.numeric(T_NBR),
      T_SEASON = as.numeric(T_SEASON),
      T_PERIOD = as.numeric(T_PERIOD),
      T_MAG = as.numeric(T_MAG),
      T_SLOPE = as.numeric(T_SLOPE),
      PVALUE = as.numeric(PVALUE),
      TREND = dplyr::case_when(
        is.na(TREND) | trimws(as.character(TREND)) == "" ~ NA_character_,
        TRUE ~ tools::toTitleCase(tolower(as.character(TREND)))
      ),
      TREND_INDET = FALSE,
      TREND_WARN = dplyr::case_when(
        is.na(TREND_WARN) | trimws(as.character(TREND_WARN)) == "" ~ NA_character_,
        TRUE ~ as.character(TREND_WARN)
      ),
      S_NBR = as.numeric(S_NBR),
      S_SEASON = as.numeric(S_SEASON),
      NOBS = as.numeric(NOBS),
      fill_qa_matched = as.logical(fill_qa_matched),
      fill_count = as.numeric(fill_count),
      fill_pct = as.numeric(fill_pct),
      max_gap = as.numeric(max_gap),
      moderate_interpolation = as.logical(moderate_interpolation),
      excessive_interpolation = as.logical(excessive_interpolation),
      severe_interpolation = as.logical(severe_interpolation),
      INTERP_PCT = as.numeric(INTERP_PCT),
      INTERP_CLASS = as.numeric(INTERP_CLASS),

      sig = !is.na(PVALUE) & PVALUE < alpha,
      abs_mag = abs(T_MAG),

      # Missing inputs are tracked separately from valid-but-unmatched combinations.
      # These remain missing in CLASS/LABEL/trend_direction_code for QA/QC.
      missing_trend_input = is.na(PVALUE) | PVALUE == missing_output_value |
        is.na(T_SLOPE) | T_SLOPE == missing_output_value,
      missing_label_input = is.na(NOBS) | NOBS == missing_output_value |
        is.na(T_NBR) | T_NBR == missing_output_value |
        is.na(S_NBR) | S_NBR == missing_output_value |
        is.na(TREND),

      qa_exclude_classification = exclude_excessively_interpolated_from_classification & excessive_interpolation,

      recovery_proxy = !missing_label_input & !is.na(T_MAG) & !is.na(T_SLOPE) &
        T_NBR >= 2 &
        T_MAG <= -recovery_magnitude_threshold &
        T_SLOPE > recovery_slope_threshold &
        (!recovery_require_significant_slope | sig),

      CLASS = dplyr::case_when(
        missing_label_input ~ missing_output_value,
        qa_exclude_classification ~ missing_output_value,
        T_NBR == 0 & S_NBR > 0 ~ 7,
        T_NBR == 0 & TREND == "Stable" ~ 1,
        T_NBR == 0 & TREND == "Negative" ~ 9,
        T_NBR == 0 & TREND == "Positive" ~ 10,
        T_NBR >= high_break_count ~ 8,
        recovery_proxy ~ 4,
        T_NBR >= 1 & !sig ~ 2,
        T_NBR >= 2 & TREND == "Negative" & sig & abs_mag >= large_magnitude_threshold ~ 5,
        T_NBR >= 1 & TREND == "Negative" & sig & abs_mag >= small_magnitude_threshold ~ 3,
        T_NBR >= 1 & TREND == "Positive" & sig & abs_mag >= small_magnitude_threshold ~ 6,
        T_NBR >= 1 & abs_mag < small_magnitude_threshold ~ 2,
        T_NBR >= 1 & TREND == "Stable" ~ 2,
        TRUE ~ 11
      ),

      LABEL = dplyr::case_when(
        CLASS == missing_output_value ~ NA_character_,
        CLASS == 1 ~ "Stable grassland",
        CLASS == 2 ~ "Climate-driven variability",
        CLASS == 3 ~ "Abrupt decline",
        CLASS == 4 ~ "Recovery trajectory",
        CLASS == 5 ~ "Sustained degradation",
        CLASS == 6 ~ "Sustained improvement",
        CLASS == 7 ~ "Phenological shift",
        CLASS == 8 ~ "Highly dynamic",
        CLASS == 9 ~ "Gradual decline",
        CLASS == 10 ~ "Gradual improvement",
        CLASS == 11 ~ "Other",
        TRUE ~ NA_character_
      ),

      trend_direction_code = dplyr::case_when(
        missing_trend_input | is.na(TREND) ~ missing_output_value,
        TREND == "Positive" ~ 1,
        TREND == "Negative" ~ -1,
        TREND == "Stable" ~ 0,
        TRUE ~ missing_output_value
      ),

      # Shapefile-safe aliases for interpolation QA fields. Full names are kept
      # in CSV outputs; these short aliases make ArcPy raster creation reliable
      # when reading ESRI Shapefile attributes.
      INTP_PCT = INTERP_PCT,
      INTP_CLS = INTERP_CLASS
    ) %>%
    dplyr::select(-sig, -abs_mag, -recovery_proxy, -missing_trend_input, -missing_label_input, -qa_exclude_classification)
}

update_cumulative_trend_file <- function(process_log_file, trend_cumulative_file) {
  if (!file.exists(process_log_file)) {
    return(invisible(NULL))
  }

  log_df <- tryCatch(
    utils::read.csv(process_log_file, stringsAsFactors = FALSE),
    error = function(e) NULL
  )

  if (is.null(log_df) || nrow(log_df) == 0) {
    return(invisible(NULL))
  }

  success_df <- log_df[log_df$status == "SUCCESS", , drop = FALSE]

  if (nrow(success_df) == 0) {
    return(invisible(NULL))
  }

  # Build a one-line cumulative log that reflects every column currently present
  # in bfast_results_log.csv. Count / numeric columns are summed across successful
  # tiles; identifier / text columns are retained as descriptive placeholders so
  # the cumulative file stays schema-aware as the processing log evolves.
  cumulative_list <- vector("list", length(names(log_df)))
  names(cumulative_list) <- names(log_df)

  for (col in names(log_df)) {
    if (col %in% c("timestamp")) {
      cumulative_list[[col]] <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    } else if (col %in% c("tile")) {
      cumulative_list[[col]] <- "ALL_SUCCESSFUL_TILES"
    } else if (col %in% c("output_file")) {
      cumulative_list[[col]] <- basename(trend_cumulative_file)
    } else if (col %in% c("status")) {
      cumulative_list[[col]] <- "CUMULATIVE_SUCCESS"
    } else if (col %in% c("message")) {
      cumulative_list[[col]] <- sprintf("Summarized %d successful tile(s) from %s", nrow(success_df), basename(process_log_file))
    } else if (is.numeric(success_df[[col]]) || is.integer(success_df[[col]])) {
      cumulative_list[[col]] <- sum(success_df[[col]], na.rm = TRUE)
    } else {
      suppressWarnings(numeric_values <- as.numeric(success_df[[col]]))
      if (all(is.na(success_df[[col]]) | !is.na(numeric_values))) {
        cumulative_list[[col]] <- sum(numeric_values, na.rm = TRUE)
      } else {
        cumulative_list[[col]] <- NA_character_
      }
    }
  }

  cumulative_df <- as.data.frame(cumulative_list, stringsAsFactors = FALSE)

  # Add explicit helper totals after preserving the bfast_results_log schema.
  cumulative_df$total_tiles_processed <- nrow(success_df)
  cumulative_df$total_log_rows <- nrow(log_df)
  cumulative_df$error_tiles <- sum(log_df$status == "ERROR", na.rm = TRUE)

  utils::write.csv(cumulative_df, trend_cumulative_file, row.names = FALSE)
}

process_bfast_tile <- function(tile) {
  start_time <- Sys.time()
  message(sprintf("Building BFAST results for tile %s ...", tile))

  file_trend_nbbreaks  <- file.path(input_dir, paste0(tile, suffix_trend_nbbreaks))
  file_trend_breaktime <- file.path(input_dir, paste0(tile, suffix_trend_breaktime))
  file_trend_breakmag  <- file.path(input_dir, paste0(tile, suffix_trend_breakmag))
  file_trend_bfast     <- file.path(input_dir, paste0(tile, suffix_trend_bfast))
  file_trend_confint   <- file.path(input_dir, paste0(tile, suffix_trend_confint))

  file_season_nbbreaks  <- file.path(input_dir, paste0(tile, suffix_season_nbbreaks))
  file_season_breaktime <- file.path(input_dir, paste0(tile, suffix_season_breaktime))
  file_season_bfast     <- file.path(input_dir, paste0(tile, suffix_season_bfast))
  file_season_confint   <- file.path(input_dir, paste0(tile, suffix_season_confint))

  file_nobs <- file.path(input_dir, paste0(tile, suffix_nobs))

  output_file <- file.path(result_output_dir, paste0(tile, result_suffix))

  trend_breaks_df <- read_two_column_file(file_trend_nbbreaks, c("ID", "T_NBR"))
  check_unique_key(trend_breaks_df, "ID", "trend_breaks_df")

  trend_break_time_df <- read_two_column_file(file_trend_breaktime, c("ID", "Time"))
  check_unique_key(trend_break_time_df, "ID", "trend_break_time_df")
  trend_break_time_df <- compute_trend_break_timing(trend_break_time_df, periods_per_season)

  trend_break_mag_df <- read_two_column_file(file_trend_breakmag, c("ID", "T_MAG"))
  check_unique_key(trend_break_mag_df, "ID", "trend_break_mag_df")

  trend_df <- compute_trend_stats(file_trend_bfast, pvalue_threshold)
  check_unique_key(trend_df, "ID", "trend_df")

  trend_confint_df <- read_confint_file(file_trend_confint, c("ID", "T_CI_LOW", "T_CI_EST", "T_CI_UPP"))
  check_unique_key(trend_confint_df, "ID", "trend_confint_df")

  season_breaks_df <- read_two_column_file(file_season_nbbreaks, c("ID", "S_NBR"))
  check_unique_key(season_breaks_df, "ID", "season_breaks_df")

  season_break_time_df <- read_two_column_file(file_season_breaktime, c("ID", "Time"))
  check_unique_key(season_break_time_df, "ID", "season_break_time_df")
  season_break_time_df <- compute_season_break_timing(season_break_time_df, periods_per_season)

  season_confint_df <- read_confint_file(file_season_confint, c("ID", "S_CI_LOW", "S_CI_EST", "S_CI_UPP"))
  check_unique_key(season_confint_df, "ID", "season_confint_df")

  nobs_df <- read_two_column_file(file_nobs, c("ID", "NOBS"))
  check_unique_key(nobs_df, "ID", "nobs_df")

  # season_bfast is required for completeness, but it is not joined as a full
  # time series to avoid creating hundreds of shapefile fields.
  stop_if_missing(file_season_bfast)

  season_df <- season_breaks_df %>%
    dplyr::left_join(season_break_time_df, by = "ID") %>%
    adjust_season_break_count()

  result_df <- trend_breaks_df %>%
    dplyr::left_join(trend_break_time_df, by = "ID") %>%
    adjust_trend_break_count() %>%
    dplyr::left_join(trend_break_mag_df, by = "ID") %>%
    dplyr::left_join(trend_df, by = "ID") %>%
    dplyr::left_join(trend_confint_df, by = "ID") %>%
    dplyr::left_join(season_df, by = "ID") %>%
    dplyr::left_join(season_confint_df, by = "ID") %>%
    dplyr::left_join(nobs_df, by = "ID")

  fill_qa_df <- if (use_fill_interpolation_qa) {
    read_fill_qa_for_tile(
      tile = tile,
      fill_pixel_qa_log_file = fill_pixel_qa_log_file,
      fill_pct_moderate_threshold = fill_pct_moderate_threshold,
      fill_pct_excessive_threshold = fill_pct_excessive_threshold,
      fill_pct_severe_threshold = fill_pct_severe_threshold,
      max_gap_moderate_threshold = max_gap_moderate_threshold,
      max_gap_excessive_threshold = max_gap_excessive_threshold,
      max_gap_severe_threshold = max_gap_severe_threshold
    )
  } else {
    NULL
  }

  if (!is.null(fill_qa_df) && nrow(fill_qa_df) > 0) {
    result_df <- result_df %>% dplyr::left_join(fill_qa_df, by = "ID")
  }

  result_df <- result_df %>%
    dplyr::mutate(
      fill_qa_matched = if ("fill_qa_matched" %in% names(.)) dplyr::coalesce(fill_qa_matched, FALSE) else FALSE,
      fill_count = if ("fill_count" %in% names(.)) as.numeric(fill_count) else NA_real_,
      fill_pct = if ("fill_pct" %in% names(.)) as.numeric(fill_pct) else NA_real_,
      max_gap = if ("max_gap" %in% names(.)) as.numeric(max_gap) else NA_real_,
      moderate_interpolation = if ("moderate_interpolation" %in% names(.)) dplyr::coalesce(moderate_interpolation, FALSE) else FALSE,
      excessive_interpolation = if ("excessive_interpolation" %in% names(.)) dplyr::coalesce(excessive_interpolation, FALSE) else FALSE,
      severe_interpolation = if ("severe_interpolation" %in% names(.)) dplyr::coalesce(severe_interpolation, FALSE) else FALSE,
      INTERP_PCT = if ("INTERP_PCT" %in% names(.)) as.numeric(INTERP_PCT) else fill_pct,
      INTERP_CLASS = if ("INTERP_CLASS" %in% names(.)) as.numeric(INTERP_CLASS) else 0,
      INTERP_LABEL = if ("INTERP_LABEL" %in% names(.)) as.character(INTERP_LABEL) else "No interpolation"
    ) %>%
    dplyr::select(ID, T_NBR, T_SEASON, T_PERIOD, T_MAG, T_SLOPE, PVALUE, TREND, TREND_WARN, TREND_INDET, S_NBR, S_SEASON,
                  T_CI_LOW, T_CI_EST, T_CI_UPP, S_CI_LOW, S_CI_EST, S_CI_UPP, NOBS,
                  fill_qa_matched, fill_count, fill_pct, max_gap, moderate_interpolation, excessive_interpolation, severe_interpolation, INTERP_PCT, INTERP_CLASS, INTERP_LABEL) %>%
    classify_bfast_results(
      alpha = alpha,
      small_magnitude_threshold = small_magnitude_threshold,
      large_magnitude_threshold = large_magnitude_threshold,
      recovery_magnitude_threshold = recovery_magnitude_threshold,
      recovery_slope_threshold = recovery_slope_threshold,
      recovery_require_significant_slope = recovery_require_significant_slope,
      high_break_count = high_break_count,
      missing_output_value = missing_output_value,
      exclude_excessively_interpolated_from_classification = exclude_excessively_interpolated_from_classification
    )

  data.table::fwrite(result_df, output_file)

  elapsed <- as.numeric(Sys.time() - start_time, units = "secs")

  list(
    result_df = result_df,
    result_file = output_file,
    process_log_row = data.frame(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      tile = tile,
      output_file = basename(output_file),
      n_rows = nrow(result_df),
      mean_nobs = ifelse(all(is.na(as.numeric(result_df$NOBS))), NA_real_, mean(as.numeric(result_df$NOBS), na.rm = TRUE)),
      min_nobs = ifelse(all(is.na(as.numeric(result_df$NOBS))), NA_real_, min(as.numeric(result_df$NOBS), na.rm = TRUE)),
      max_nobs = ifelse(all(is.na(as.numeric(result_df$NOBS))), NA_real_, max(as.numeric(result_df$NOBS), na.rm = TRUE)),
      has_season_bfast = file.exists(file_season_bfast),
      has_trend_confint = file.exists(file_trend_confint),
      has_season_confint = file.exists(file_season_confint),
      has_nobs = file.exists(file_nobs),
      valid_nobs_count = count_valid_field(result_df$NOBS),
      missing_nobs_count = count_missing_field(result_df$NOBS),
      missing_trend_pvalue_count = sum(is.na(result_df$PVALUE), na.rm = TRUE),
      missing_trend_slope_count = sum(is.na(result_df$T_SLOPE), na.rm = TRUE),
      missing_trend_input_count = sum(is.na(result_df$PVALUE) | result_df$PVALUE == missing_output_value | is.na(result_df$T_SLOPE) | result_df$T_SLOPE == missing_output_value, na.rm = TRUE),
      valid_trend_input_count = nrow(result_df) - sum(is.na(result_df$PVALUE) | result_df$PVALUE == missing_output_value | is.na(result_df$T_SLOPE) | result_df$T_SLOPE == missing_output_value, na.rm = TRUE),
      missing_trend_output_count = count_missing_field(result_df$TREND),
      valid_trend_output_count = count_valid_field(result_df$TREND),
      missing_trend_code_count = count_missing_field(result_df$trend_direction_code),
      valid_trend_code_count = count_valid_field(result_df$trend_direction_code),
      missing_label_input_count = sum(is.na(result_df$NOBS) | result_df$NOBS == missing_output_value | is.na(result_df$T_NBR) | result_df$T_NBR == missing_output_value | is.na(result_df$S_NBR) | result_df$S_NBR == missing_output_value | is.na(result_df$TREND), na.rm = TRUE),
      valid_label_input_count = nrow(result_df) - sum(is.na(result_df$NOBS) | result_df$NOBS == missing_output_value | is.na(result_df$T_NBR) | result_df$T_NBR == missing_output_value | is.na(result_df$S_NBR) | result_df$S_NBR == missing_output_value | is.na(result_df$TREND), na.rm = TRUE),
      missing_class_count = count_missing_field(result_df$CLASS),
      valid_class_count = count_valid_field(result_df$CLASS),
      missing_label_count = count_missing_field(result_df$LABEL),
      valid_label_count = count_valid_field(result_df$LABEL),
      positive_count = sum(result_df$TREND == "Positive", na.rm = TRUE),
      negative_count = sum(result_df$TREND == "Negative", na.rm = TRUE),
      stable_count = sum(result_df$TREND == "Stable", na.rm = TRUE),
      indeterminate_count = 0,
      perfect_fit_warning_count = sum(!is.na(result_df$TREND_WARN) & grepl("essentially perfect fit", result_df$TREND_WARN, ignore.case = TRUE), na.rm = TRUE),
      trend_warning_count = sum(!is.na(result_df$TREND_WARN), na.rm = TRUE),
      fill_qa_matched_count = if ("fill_qa_matched" %in% names(result_df)) sum(result_df$fill_qa_matched, na.rm = TRUE) else 0,
      moderate_interpolation_count = if ("moderate_interpolation" %in% names(result_df)) sum(result_df$moderate_interpolation, na.rm = TRUE) else 0,
      excessive_interpolation_count = if ("excessive_interpolation" %in% names(result_df)) sum(result_df$excessive_interpolation, na.rm = TRUE) else 0,
      severe_interpolation_count = if ("severe_interpolation" %in% names(result_df)) sum(result_df$severe_interpolation, na.rm = TRUE) else 0,
      interp_class_0_count = if ("INTERP_CLASS" %in% names(result_df)) sum(result_df$INTERP_CLASS == 0, na.rm = TRUE) else NA_integer_,
      interp_class_1_count = if ("INTERP_CLASS" %in% names(result_df)) sum(result_df$INTERP_CLASS == 1, na.rm = TRUE) else NA_integer_,
      interp_class_2_count = if ("INTERP_CLASS" %in% names(result_df)) sum(result_df$INTERP_CLASS == 2, na.rm = TRUE) else NA_integer_,
      interp_class_3_count = if ("INTERP_CLASS" %in% names(result_df)) sum(result_df$INTERP_CLASS == 3, na.rm = TRUE) else NA_integer_,
      interp_class_4_count = if ("INTERP_CLASS" %in% names(result_df)) sum(result_df$INTERP_CLASS == 4, na.rm = TRUE) else NA_integer_,
      excessive_interpolation_excluded_count = if ("excessive_interpolation" %in% names(result_df) && exclude_excessively_interpolated_from_classification) sum(result_df$excessive_interpolation & is_missing_value(result_df$CLASS), na.rm = TRUE) else 0,
      stable_grassland_count = sum(result_df$CLASS == 1, na.rm = TRUE),
      climate_variability_count = sum(result_df$CLASS == 2, na.rm = TRUE),
      abrupt_decline_count = sum(result_df$CLASS == 3, na.rm = TRUE),
      recovery_trajectory_count = sum(result_df$CLASS == 4, na.rm = TRUE),
      sustained_degradation_count = sum(result_df$CLASS == 5, na.rm = TRUE),
      sustained_improvement_count = sum(result_df$CLASS == 6, na.rm = TRUE),
      phenology_count = sum(result_df$CLASS == 7, na.rm = TRUE),
      dynamic_count = sum(result_df$CLASS == 8, na.rm = TRUE),
      gradual_decline_count = sum(result_df$CLASS == 9, na.rm = TRUE),
      gradual_improvement_count = sum(result_df$CLASS == 10, na.rm = TRUE),
      other_count = sum(result_df$CLASS == 11, na.rm = TRUE),
      trend_mass_balance_ok = mass_balance_ok(nrow(result_df), count_valid_field(result_df$trend_direction_code), count_missing_field(result_df$trend_direction_code)),
      class_mass_balance_ok = mass_balance_ok(nrow(result_df), count_valid_field(result_df$CLASS), count_missing_field(result_df$CLASS)),
      label_mass_balance_ok = mass_balance_ok(nrow(result_df), count_valid_field(result_df$LABEL), count_missing_field(result_df$LABEL)),
      nobs_mass_balance_ok = mass_balance_ok(nrow(result_df), count_valid_field(result_df$NOBS), count_missing_field(result_df$NOBS)),
      status = "SUCCESS",
      message = NA_character_,
      elapsed_seconds = elapsed,
      stringsAsFactors = FALSE
    )
  )
}

join_results_to_shape <- function(tile, result_file) {
  start_time <- Sys.time()
  message(sprintf("Joining results to shapefile for tile %s ...", tile))

  shape_file <- file.path(shape_dir, paste0(shape_prefix, tile, ".shp"))
  output_file <- file.path(join_output_dir, paste0(shape_prefix, tile, shape_out_suffix))

  shape_mismatch_file <- file.path(join_output_dir, paste0(shape_prefix, tile, shape_mismatch_suffix))
  result_mismatch_file <- file.path(join_output_dir, paste0(shape_prefix, tile, result_mismatch_suffix))

  stop_if_missing(shape_file)
  stop_if_missing(result_file)

  shp <- sf::st_read(shape_file, quiet = TRUE)

  if (!("pointid" %in% names(shp))) {
    stop(sprintf("Field 'pointid' not found in shapefile: %s", shape_file), call. = FALSE)
  }

  shp$pointid <- as.numeric(shp$pointid)
  check_unique_key(shp, "pointid", "shapefile")

  results <- as.data.frame(data.table::fread(result_file))
  results$ID <- as.numeric(results$ID)
  check_unique_key(results, "ID", "results file")

  results$JOIN_FLAG <- 1

  shp_out <- shp %>%
    dplyr::left_join(results, by = c("pointid" = "ID"))

  shp_unmatched <- shp %>%
    dplyr::filter(!(pointid %in% results$ID)) %>%
    sf::st_drop_geometry()

  result_unmatched <- results %>%
    dplyr::filter(!(ID %in% shp$pointid)) %>%
    dplyr::select(-JOIN_FLAG)

  utils::write.csv(shp_unmatched, shape_mismatch_file, row.names = FALSE)
  utils::write.csv(result_unmatched, result_mismatch_file, row.names = FALSE)

  n_shape_features <- nrow(shp)
  n_result_rows <- nrow(results)
  n_shape_unmatched <- nrow(shp_unmatched)
  n_result_unmatched <- nrow(result_unmatched)

  shp_out <- shp_out %>%
    dplyr::select(-JOIN_FLAG)

  # Remove any prior output shapefile and sidecar files before writing.
  # The helper only deletes files that actually exist, which prevents harmless
  # GDAL warnings about trying to delete a dataset before it has been created.
  delete_existing_shapefile(output_file)

  # ESRI Shapefiles limit field names to 10 characters. sf/GDAL may warn that
  # names were abbreviated even though the write succeeds. Suppress only that
  # expected warning so other write problems still appear.
  withCallingHandlers(
    sf::st_write(shp_out, output_file, quiet = TRUE),
    warning = function(w) {
      msg <- conditionMessage(w)
      if (grepl("Field names abbreviated for ESRI Shapefile driver", msg, fixed = TRUE)) {
        invokeRestart("muffleWarning")
      }
    }
  )

  elapsed <- as.numeric(Sys.time() - start_time, units = "secs")

  data.frame(
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    tile = tile,
    shapefile = basename(shape_file),
    result_file = basename(result_file),
    output_shapefile = basename(output_file),
    shape_unmatched_file = basename(shape_mismatch_file),
    result_unmatched_file = basename(result_mismatch_file),
    n_shape_features = n_shape_features,
    n_result_rows = n_result_rows,
    n_shape_matched = n_shape_features - n_shape_unmatched,
    n_result_matched = n_result_rows - n_result_unmatched,
    n_shape_unmatched = n_shape_unmatched,
    n_result_unmatched = n_result_unmatched,
    status = "SUCCESS",
    message = NA_character_,
    elapsed_seconds = elapsed,
    stringsAsFactors = FALSE
  )
}

#==============================#
# Main execution
#==============================#

if (!dir.exists(input_dir)) {
  stop(sprintf("Input directory does not exist: %s", input_dir), call. = FALSE)
}

if (!dir.exists(shape_dir)) {
  stop(sprintf("Shapefile directory does not exist: %s", shape_dir), call. = FALSE)
}

dir.create(result_output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(join_output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

tile_list <- get_tiles_with_complete_bfast_outputs(
  input_dir = input_dir,
  suffix_trend_nbbreaks = suffix_trend_nbbreaks,
  suffix_trend_breaktime = suffix_trend_breaktime,
  suffix_trend_breakmag = suffix_trend_breakmag,
  suffix_trend_bfast = suffix_trend_bfast,
  suffix_trend_confint = suffix_trend_confint,
  suffix_season_nbbreaks = suffix_season_nbbreaks,
  suffix_season_breaktime = suffix_season_breaktime,
  suffix_season_bfast = suffix_season_bfast,
  suffix_season_confint = suffix_season_confint,
  suffix_nobs = suffix_nobs
)

message(sprintf(
  "Found %d tile(s) with a complete set of BFAST output files.",
  length(tile_list)
))

completed_tiles <- get_completed_tiles(process_log_file)

if (length(completed_tiles) > 0) {
  message(sprintf(
    "Found %d tile(s) already marked SUCCESS in bfast_results_log.csv.",
    length(completed_tiles)
  ))
}

bfast_log_rows <- list()
join_log_rows <- list()
pixel_accounting_rows <- list()
dropped_pixel_reason_rows <- list()

for (tile in tile_list) {
  tile <- as.character(tile)

  if (tile %in% completed_tiles) {
    message(sprintf(
      "Tile %s already successfully processed according to bfast_results_log.csv. Skipping.",
      tile
    ))
    next
  }

  bfast_result <- tryCatch(
    process_bfast_tile(tile),
    error = function(e) {
      message(sprintf("ERROR building BFAST results for tile %s: %s", tile, e$message))

      list(
        result_df = NULL,
        result_file = file.path(result_output_dir, paste0(tile, result_suffix)),
        process_log_row = data.frame(
          timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
          tile = tile,
          output_file = paste0(tile, result_suffix),
          n_rows = NA_integer_,
          mean_nobs = NA_real_,
          min_nobs = NA_real_,
          max_nobs = NA_real_,
          has_season_bfast = NA,
          has_trend_confint = NA,
          has_season_confint = NA,
          has_nobs = NA,
          valid_nobs_count = NA_integer_,
          missing_nobs_count = NA_integer_,
          missing_trend_pvalue_count = NA_integer_,
          missing_trend_slope_count = NA_integer_,
          missing_trend_input_count = NA_integer_,
          valid_trend_input_count = NA_integer_,
          missing_trend_output_count = NA_integer_,
          valid_trend_output_count = NA_integer_,
          missing_trend_code_count = NA_integer_,
          valid_trend_code_count = NA_integer_,
          missing_label_input_count = NA_integer_,
          valid_label_input_count = NA_integer_,
          missing_class_count = NA_integer_,
          valid_class_count = NA_integer_,
          missing_label_count = NA_integer_,
          valid_label_count = NA_integer_,
          positive_count = NA_integer_,
          negative_count = NA_integer_,
          stable_count = NA_integer_,
          indeterminate_count = NA_integer_,
          perfect_fit_warning_count = NA_integer_,
          trend_warning_count = NA_integer_,
          stable_grassland_count = NA_integer_,
          climate_variability_count = NA_integer_,
          abrupt_decline_count = NA_integer_,
          recovery_trajectory_count = NA_integer_,
          sustained_degradation_count = NA_integer_,
          sustained_improvement_count = NA_integer_,
          phenology_count = NA_integer_,
          dynamic_count = NA_integer_,
          gradual_decline_count = NA_integer_,
          gradual_improvement_count = NA_integer_,
          other_count = NA_integer_,
          trend_mass_balance_ok = NA,
          class_mass_balance_ok = NA,
          label_mass_balance_ok = NA,
          nobs_mass_balance_ok = NA,
          status = "ERROR",
          message = e$message,
          elapsed_seconds = NA_real_,
          stringsAsFactors = FALSE
        )
      )
    }
  )

  bfast_log_rows[[length(bfast_log_rows) + 1]] <- bfast_result$process_log_row

  if (!is.null(bfast_result$result_df)) {
    join_log_row <- tryCatch(
      join_results_to_shape(tile, bfast_result$result_file),
      error = function(e) {
        message(sprintf("ERROR joining shapefile for tile %s: %s", tile, e$message))

        data.frame(
          timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
          tile = tile,
          shapefile = paste0(shape_prefix, tile, ".shp"),
          result_file = basename(bfast_result$result_file),
          output_shapefile = paste0(shape_prefix, tile, shape_out_suffix),
          shape_unmatched_file = paste0(shape_prefix, tile, shape_mismatch_suffix),
          result_unmatched_file = paste0(shape_prefix, tile, result_mismatch_suffix),
          n_shape_features = NA_integer_,
          n_result_rows = NA_integer_,
          n_shape_matched = NA_integer_,
          n_result_matched = NA_integer_,
          n_shape_unmatched = NA_integer_,
          n_result_unmatched = NA_integer_,
          status = "ERROR",
          message = e$message,
          elapsed_seconds = NA_real_,
          stringsAsFactors = FALSE
        )
      }
    )

    join_log_rows[[length(join_log_rows) + 1]] <- join_log_row

    pixel_accounting_rows[[length(pixel_accounting_rows) + 1]] <- make_pixel_accounting_row(
      tile = tile,
      process_log_row = bfast_result$process_log_row,
      join_log_row = join_log_row
    )

    dropped_reason_row <- make_dropped_pixel_reason_log(
      tile = tile,
      result_df = bfast_result$result_df,
      shape_mismatch_file = file.path(join_output_dir, paste0(shape_prefix, tile, shape_mismatch_suffix)),
      result_mismatch_file = file.path(join_output_dir, paste0(shape_prefix, tile, result_mismatch_suffix))
    )

    if (!is.null(dropped_reason_row) && nrow(dropped_reason_row) > 0) {
      dropped_pixel_reason_rows[[length(dropped_pixel_reason_rows) + 1]] <- dropped_reason_row
    }
  } else {
    pixel_accounting_rows[[length(pixel_accounting_rows) + 1]] <- make_pixel_accounting_row(
      tile = tile,
      process_log_row = bfast_result$process_log_row,
      join_log_row = NULL
    )
  }
}

if (length(bfast_log_rows) > 0) {
  bfast_log_df <- do.call(rbind, bfast_log_rows)
  append_csv(bfast_log_df, process_log_file)
}

update_cumulative_trend_file(
  process_log_file = process_log_file,
  trend_cumulative_file = trend_cumulative_file
)

if (length(join_log_rows) > 0) {
  join_log_df <- do.call(rbind, join_log_rows)
  append_csv(join_log_df, join_summary_log_file)
}

if (length(pixel_accounting_rows) > 0) {
  pixel_accounting_df <- do.call(rbind, pixel_accounting_rows)
  append_csv(pixel_accounting_df, pixel_accounting_log_file)
}

if (length(dropped_pixel_reason_rows) > 0) {
  dropped_pixel_reason_df <- dplyr::bind_rows(dropped_pixel_reason_rows)
  append_csv(dropped_pixel_reason_df, dropped_pixel_reason_log_file)
}

message(sprintf("BFAST processing log written to: %s", process_log_file))
message(sprintf("Trend cumulative totals written to: %s", trend_cumulative_file))
message(sprintf("Join summary log written to: %s", join_summary_log_file))
message("All processing complete.")
