#--------------------------------------------------------------------------------------
# Name:         RScript_Build_MasterProcessingLog.R
# Author:       Shawn Hutchinson
# Date Created: April 27, 2026
# Last Updated: May 9, 2026
#
# Description:
#   Combines Fishnet50K tile list with extract, NA-fill, BFAST, and join logs.
#   Produces one master processing summary and one progress summary.
#
#   The BFAST log may include monitoring fields produced by the updated
#   BFAST results workflow, including mean/min/max NOBS and flags for
#   season_bfast, trend confidence interval, season confidence interval,
#   and NOBS output availability. These fields are carried forward with
#   the bfast_ prefix automatically.
#--------------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(data.table)
  library(dplyr)
  library(stringr)
})

#==============================#
# User settings
#==============================#

log_dir <- "D:/Research/Projects/BFAST_2001_2025/BFAST_H0.15/logs"

fishnet_file <- file.path(log_dir, "Fishnet50K.csv")
extract_log_file <- file.path(log_dir, "extract_log.csv")
na_fill_log_file <- file.path(log_dir, "na_fill_log.csv")
bfast_log_file <- file.path(log_dir, "bfast_results_log.csv")
join_log_file <- file.path(log_dir, "join_results_log.csv")

master_output_file <- file.path(log_dir, "Fishnet50K_processing_summary.csv")
progress_output_file <- file.path(log_dir, "Fishnet50K_processing_progress.csv")

#==============================#
# Helper functions
#==============================#

read_if_exists <- function(path) {
  if (!file.exists(path)) {
    warning(sprintf("File not found: %s", path))
    return(NULL)
  }
  as.data.frame(data.table::fread(path))
}

standardize_tile <- function(x) {
  as.character(as.integer(x))
}

extract_tile_from_text <- function(x) {
  # Pulls tile number from names like Centroids_255.csv or Centroids_255_fill.csv
  stringr::str_extract(x, "(?<=Centroids_)\\d+")
}

latest_by_tile <- function(df) {
  if (is.null(df) || nrow(df) == 0) {
    return(NULL)
  }

  if (!("tile" %in% names(df))) {
    stop("Input log is missing a tile field.", call. = FALSE)
  }

  df$tile <- standardize_tile(df$tile)

  if ("timestamp" %in% names(df)) {
    df <- df %>%
      dplyr::mutate(.row_order = dplyr::row_number()) %>%
      dplyr::arrange(tile, .row_order)
  } else {
    df <- df %>%
      dplyr::mutate(.row_order = dplyr::row_number()) %>%
      dplyr::arrange(tile, .row_order)
  }

  df %>%
    dplyr::group_by(tile) %>%
    dplyr::slice_tail(n = 1) %>%
    dplyr::ungroup() %>%
    dplyr::select(-.row_order)
}

rename_with_prefix <- function(df, prefix, keep_tile = TRUE) {
  if (is.null(df)) {
    return(NULL)
  }

  keep_names <- if (keep_tile) "tile" else character(0)

  names(df) <- ifelse(
    names(df) %in% keep_names,
    names(df),
    paste0(prefix, names(df))
  )

  df
}

#==============================#
# Read input files
#==============================#

fishnet <- read_if_exists(fishnet_file)

if (is.null(fishnet)) {
  stop(sprintf("Fishnet file not found: %s", fishnet_file), call. = FALSE)
}

if (!("tile" %in% names(fishnet))) {
  stop("Fishnet50K.csv must contain a field named 'tile'.", call. = FALSE)
}

fishnet <- fishnet %>%
  dplyr::mutate(tile = standardize_tile(tile))

extract_log <- read_if_exists(extract_log_file)
na_fill_log <- read_if_exists(na_fill_log_file)
bfast_log <- read_if_exists(bfast_log_file)
join_log <- read_if_exists(join_log_file)

#==============================#
# Prepare logs
#==============================#

# Extract log
if (!is.null(extract_log)) {
  extract_log$tile <- standardize_tile(extract_log$tile)
  extract_log <- latest_by_tile(extract_log)
  extract_log <- rename_with_prefix(extract_log, "extract_")
}

# NA-fill log may have missing tile values, so derive tile from input_file/output_file
if (!is.null(na_fill_log)) {
  if (!("tile" %in% names(na_fill_log))) {
    na_fill_log$tile <- NA_character_
  }

  na_fill_log$tile <- as.character(na_fill_log$tile)

  missing_tile <- is.na(na_fill_log$tile) | na_fill_log$tile == "" | na_fill_log$tile == "NA"

  if ("input_file" %in% names(na_fill_log)) {
    na_fill_log$tile[missing_tile] <- extract_tile_from_text(na_fill_log$input_file[missing_tile])
  }

  missing_tile <- is.na(na_fill_log$tile) | na_fill_log$tile == "" | na_fill_log$tile == "NA"

  if ("output_file" %in% names(na_fill_log)) {
    na_fill_log$tile[missing_tile] <- extract_tile_from_text(na_fill_log$output_file[missing_tile])
  }

  na_fill_log$tile <- standardize_tile(na_fill_log$tile)
  na_fill_log <- latest_by_tile(na_fill_log)
  na_fill_log <- rename_with_prefix(na_fill_log, "na_fill_")
}

# BFAST results log
if (!is.null(bfast_log)) {
  bfast_log$tile <- standardize_tile(bfast_log$tile)
  bfast_log <- latest_by_tile(bfast_log)
  bfast_log <- rename_with_prefix(bfast_log, "bfast_")
}

# Join results log
if (!is.null(join_log)) {
  join_log$tile <- standardize_tile(join_log$tile)
  join_log <- latest_by_tile(join_log)
  join_log <- rename_with_prefix(join_log, "join_")
}

#==============================#
# Join logs to Fishnet50K
#==============================#

master <- fishnet

if (!is.null(extract_log)) {
  master <- master %>%
    dplyr::left_join(extract_log, by = "tile")
}

if (!is.null(na_fill_log)) {
  master <- master %>%
    dplyr::left_join(na_fill_log, by = "tile")
}

if (!is.null(bfast_log)) {
  master <- master %>%
    dplyr::left_join(bfast_log, by = "tile")
}

if (!is.null(join_log)) {
  master <- master %>%
    dplyr::left_join(join_log, by = "tile")
}

#==============================#
# Add completion fields
#==============================#

master <- master %>%
  dplyr::mutate(
    extract_complete = extract_status == "SUCCESS",
    na_fill_complete = na_fill_status == "SUCCESS",
    bfast_complete = bfast_status == "SUCCESS",
    join_complete = join_status == "SUCCESS",

    processing_complete =
      extract_complete &
      na_fill_complete &
      bfast_complete &
      join_complete,

    completed_steps =
      rowSums(
        dplyr::across(
          c(extract_complete, na_fill_complete, bfast_complete, join_complete),
          ~ ifelse(is.na(.x), FALSE, .x)
        )
      ),

    total_steps = 4,
    percent_steps_complete = round((completed_steps / total_steps) * 100, 2)
  )

#==============================#
# Create progress summary
#==============================#

total_tiles <- nrow(master)
tiles_complete <- sum(master$processing_complete, na.rm = TRUE)
percent_tiles_complete <- round((tiles_complete / total_tiles) * 100, 2)

progress_summary <- data.frame(
  timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  total_tiles = total_tiles,
  extract_complete = sum(master$extract_complete, na.rm = TRUE),
  na_fill_complete = sum(master$na_fill_complete, na.rm = TRUE),
  bfast_complete = sum(master$bfast_complete, na.rm = TRUE),
  join_complete = sum(master$join_complete, na.rm = TRUE),
  fully_complete_tiles = tiles_complete,
  percent_fully_complete = percent_tiles_complete,
  stringsAsFactors = FALSE
)

#==============================#
# Write outputs
#==============================#

data.table::fwrite(master, master_output_file)
data.table::fwrite(progress_summary, progress_output_file)

message(sprintf("Master processing summary written to: %s", master_output_file))
message(sprintf("Progress summary written to: %s", progress_output_file))
message(sprintf(
  "Processing complete for %d of %d tiles: %.2f%%",
  tiles_complete,
  total_tiles,
  percent_tiles_complete
))
