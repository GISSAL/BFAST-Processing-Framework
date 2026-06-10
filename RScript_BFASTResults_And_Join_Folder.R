#--------------------------------------------------------------------------------------
# Name:         RScript_BFASTResults_And_Join_Folder.R
# Author:       Shawn Hutchinson
# Date Created: April 27, 2026
# Last Updated: May 13, 2026
#
# Description:
#   End-to-end workflow that:
#     1) reads BFAST output files for all tiles in a folder
#     2) produces a summary CSV containing:
#          - ID
#          - T_NBR
#          - T_SEASON
#          - T_PERIOD
#          - T_MAG
#          - T_SLOPE
#          - PVALUE
#          - TREND
#          - S_NBR
#          - S_SEASON
#          - CLASS
#          - LABEL
#          - trend_direction_code
#          - NOBS
#          - T_CI_LOW / T_CI_EST / T_CI_UPP
#          - S_CI_LOW / S_CI_EST / S_CI_UPP
#     3) appends a BFAST processing log
#     4) updates a one-line cumulative trend totals CSV
#     5) joins the results CSV back to the matching centroid shapefile by:
#          - shapefile field: pointid
#          - results field:   ID
#     6) writes a new shapefile with suffix "_Result"
#     7) writes mismatch report CSVs for QA/QC
#     8) appends a join summary log
#     9) Tiles already marked SUCCESS in bfast_results_log.csv are skipped.
#
# Notes:
#   - Update only the user settings section below.
#   - Input files are matched by ID to reduce the risk of row-order mismatches.
#   - Duplicate IDs / pointids are checked before joins to prevent silent corruption.
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
result_output_dir <- "D:/Research/Projects/BFAST_2001_2025/BFAST_H0.15/results"
shape_dir <- "D:/Research/Projects/BFAST_2001_2025/BFAST/tiles"
join_output_dir <- "D:/Research/Projects/BFAST_2001_2025/BFAST_H0.15/tile_results"
log_dir <- "D:/Research/Projects/BFAST_2001_2025/BFAST_H0.15/logs"

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

process_log_file <- file.path(log_dir, "bfast_results_log.csv")
trend_cumulative_file <- file.path(log_dir, "bfast_trend_cumulative.csv")
join_summary_log_file <- file.path(log_dir, "join_results_log.csv")

#==============================#
# Helper functions
#==============================#

stop_if_missing <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("Required file not found: %s", path), call. = FALSE)
  }
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
        coef_table <- tryCatch(
          summary(fit)$coefficients,
          error = function(e) NULL
        )

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
    stringsAsFactors = FALSE
  ) %>%
    dplyr::mutate(
      TREND = dplyr::case_when(
        is.na(PVALUE) | is.na(T_SLOPE) ~ "Stable",
        PVALUE >= pvalue_threshold   ~ "Stable",
        T_SLOPE > 0                  ~ "Positive",
        T_SLOPE < 0                  ~ "Negative",
        TRUE                         ~ "Stable"
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
                                   high_break_count) {
  df %>%
    dplyr::mutate(
      ID = as.numeric(ID),
      T_NBR = as.numeric(T_NBR),
      T_SEASON = as.numeric(T_SEASON),
      T_PERIOD = as.numeric(T_PERIOD),
      T_MAG = as.numeric(T_MAG),
      T_SLOPE = as.numeric(T_SLOPE),
      PVALUE = as.numeric(PVALUE),
      TREND = tools::toTitleCase(tolower(as.character(TREND))),
      S_NBR = as.numeric(S_NBR),
      S_SEASON = as.numeric(S_SEASON),

      sig = !is.na(PVALUE) & PVALUE < alpha,
      abs_mag = abs(T_MAG),
      recovery_proxy = !is.na(T_NBR) & !is.na(T_MAG) & !is.na(T_SLOPE) &
        T_NBR >= 2 &
        T_MAG <= -recovery_magnitude_threshold &
        T_SLOPE > recovery_slope_threshold &
        (!recovery_require_significant_slope | sig),

      CLASS = dplyr::case_when(
        T_NBR == 0 & S_NBR > 0 ~ 7,
        T_NBR == 0 & TREND == "Stable" ~ 1,
        T_NBR >= high_break_count ~ 8,
        recovery_proxy ~ 4,
        T_NBR >= 1 & !sig ~ 2,
        T_NBR >= 2 & TREND == "Negative" & sig & abs_mag >= large_magnitude_threshold ~ 5,
        T_NBR >= 1 & TREND == "Negative" & sig & abs_mag >= small_magnitude_threshold ~ 3,
        T_NBR >= 1 & TREND == "Positive" & sig & abs_mag >= small_magnitude_threshold ~ 6,
        T_NBR >= 1 & abs_mag < small_magnitude_threshold ~ 2,
        T_NBR >= 1 & TREND == "Stable" ~ 2,
        TRUE ~ 8
      ),

      LABEL = dplyr::case_when(
        CLASS == 1 ~ "Stable grassland",
        CLASS == 2 ~ "Interannual climate variability",
        CLASS == 3 ~ "Abrupt productivity decline",
        CLASS == 4 ~ "Recovery / resilience",
        CLASS == 5 ~ "Persistent decline",
        CLASS == 6 ~ "Persistent improvement",
        CLASS == 7 ~ "Phenological shift",
        CLASS == 8 ~ "Highly dynamic / unstable",
        TRUE ~ "Unclassified"
      ),

      trend_direction_code = dplyr::case_when(
        TREND == "Positive" ~ 1,
        TREND == "Negative" ~ -1,
        TRUE ~ 0
      )
    ) %>%
    dplyr::select(-sig, -abs_mag, -recovery_proxy)
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
    dplyr::left_join(nobs_df, by = "ID") %>%
    dplyr::select(ID, T_NBR, T_SEASON, T_PERIOD, T_MAG, T_SLOPE, PVALUE, TREND, S_NBR, S_SEASON,
                  T_CI_LOW, T_CI_EST, T_CI_UPP, S_CI_LOW, S_CI_EST, S_CI_UPP, NOBS) %>%
    classify_bfast_results(
      alpha = alpha,
      small_magnitude_threshold = small_magnitude_threshold,
      large_magnitude_threshold = large_magnitude_threshold,
      recovery_magnitude_threshold = recovery_magnitude_threshold,
      recovery_slope_threshold = recovery_slope_threshold,
      recovery_require_significant_slope = recovery_require_significant_slope,
      high_break_count = high_break_count
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
      positive_count = sum(result_df$TREND == "Positive", na.rm = TRUE),
      negative_count = sum(result_df$TREND == "Negative", na.rm = TRUE),
      stable_count = sum(result_df$TREND == "Stable", na.rm = TRUE),
      stable_grassland_count = sum(result_df$CLASS == 1, na.rm = TRUE),
      climate_variability_count = sum(result_df$CLASS == 2, na.rm = TRUE),
      decline_count = sum(result_df$CLASS == 3, na.rm = TRUE),
      recovery_count = sum(result_df$CLASS == 4, na.rm = TRUE),
      persistent_decline_count = sum(result_df$CLASS == 5, na.rm = TRUE),
      improvement_count = sum(result_df$CLASS == 6, na.rm = TRUE),
      phenology_count = sum(result_df$CLASS == 7, na.rm = TRUE),
      dynamic_count = sum(result_df$CLASS == 8, na.rm = TRUE),
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

  sf::st_write(shp_out, output_file, delete_layer = TRUE, quiet = TRUE)

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
          positive_count = NA_integer_,
          negative_count = NA_integer_,
          stable_count = NA_integer_,
          stable_grassland_count = NA_integer_,
          climate_variability_count = NA_integer_,
          decline_count = NA_integer_,
          recovery_count = NA_integer_,
          persistent_decline_count = NA_integer_,
          improvement_count = NA_integer_,
          phenology_count = NA_integer_,
          dynamic_count = NA_integer_,
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

message(sprintf("BFAST processing log written to: %s", process_log_file))
message(sprintf("Trend cumulative totals written to: %s", trend_cumulative_file))
message(sprintf("Join summary log written to: %s", join_summary_log_file))
message("All processing complete.")
