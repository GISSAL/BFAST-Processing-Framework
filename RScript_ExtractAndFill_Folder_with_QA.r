#--------------------------------------------------------------------------------------
# Name:         RScript_ExtractAndFill_Folder_with_QA_SEPARATE_DIRS.R
# Author:       Shawn Hutchinson
# Date Created: April 27, 2026
# Last Updated: June 15, 2026
#
# Description:
#   End-to-end workflow that:
#     1) Extract raster values at centroid shapefile locations
#     2) Screen/fill NA values in the extracted row-wise time series
#     3) Tiles already marked SUCCESS in extract_log.csv are skipped.
#
#   For each tile, this script:
#     - reads the centroid shapefile
#     - extracts raster stack values at point locations
#     - writes the raw extracted CSV to raw_output_dir
#     - fills NA values in the extracted raster-value columns
#     - writes the filled CSV to fill_output_dir
#
#   The first output column is the shapefile field "pointid".
#   The "pointid" field is preserved unchanged and is NOT included in interpolation.
#
#   Raw extracted CSVs and filled CSVs are written to separate directories.
#
#   Separate log files are maintained and appended if they already exist:
#     - extract_log.csv
#     - na_fill_log.csv
#     - na_fill_pixel_qa_log.csv
#     - na_fill_summary_qa_log.csv
#
# Notes:
#   - Tiles are discovered automatically from shapefiles named like:
#     Centroids_277.shp
#   - Update only the user settings section below.
#   - Output CSV files are written without column names by default.
#   - extract_log.csv and na_fill_log.csv include both basename and full path
#     fields for the raw and filled outputs.
#   - Missing values are filled in this order:
#       1) linear interpolation with zoo::na.approx()
#       2) forward fill with zoo::na.locf()
#       3) backward fill with zoo::na.locf(fromLast = TRUE)
#   - Pixel-level and tile-level QA logs are created so the amount and pattern of
#     missing-value replacement can be reviewed before using the filled values in BFAST.
#--------------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(raster)
  library(sf)
  library(zoo)
  library(tools)
})

#==============================#
# User settings
#==============================#

raster_dir      <- "D:/Research/Projects/BFAST_2001_2025/MOD13Q1/NDVI"
shape_dir       <- "D:/Research/Projects/BFAST_2001_2025/BFAST/tiles"
raw_output_dir  <- "D:/Research/Projects/BFAST_2001_2025/BFAST_H0.15_Test/extracted"
fill_output_dir <- "D:/Research/Projects/BFAST_2001_2025/BFAST_H0.15_Test/filled"
log_dir         <- "D:/Research/Projects/BFAST_2001_2025/BFAST_H0.15_Test/logs"

raster_pattern <- "\\.tif$"
shape_prefix   <- "Centroids_"
shape_pattern  <- paste0("^", shape_prefix, "[0-9]+\\.shp$")

include_pointid_column <- TRUE
raw_output_suffix  <- ".csv"
fill_output_suffix <- "_fill.csv"

extract_log_file <- file.path(log_dir, "extract_log.csv")
na_fill_log_file <- file.path(log_dir, "na_fill_log.csv")
na_fill_pixel_qa_log_file <- file.path(log_dir, "na_fill_pixel_qa_log.csv")
na_fill_summary_qa_log_file <- file.path(log_dir, "na_fill_summary_qa_log.csv")

#==============================#
# Helper functions
#==============================#

stop_if_missing_dir <- function(path, label) {
  if (!dir.exists(path)) {
    stop(sprintf("%s does not exist: %s", label, path), call. = FALSE)
  }
}

append_log <- function(log_df, log_file) {
  if (file.exists(log_file)) {
    existing_log <- tryCatch(
      utils::read.csv(log_file, stringsAsFactors = FALSE),
      error = function(e) {
        warning(sprintf("Existing log could not be read. Creating new log file: %s", log_file))
        NULL
      }
    )

    if (!is.null(existing_log)) {
      missing_cols <- setdiff(names(log_df), names(existing_log))
      for (col in missing_cols) existing_log[[col]] <- NA

      extra_cols <- setdiff(names(existing_log), names(log_df))
      for (col in extra_cols) log_df[[col]] <- NA

      log_df <- log_df[, names(existing_log), drop = FALSE]
      combined_log <- rbind(existing_log, log_df)
    } else {
      combined_log <- log_df
    }
  } else {
    combined_log <- log_df
  }

  utils::write.csv(combined_log, log_file, row.names = FALSE)
}

get_completed_tiles <- function(extract_log_file) {
  if (!file.exists(extract_log_file)) {
    return(character(0))
  }

  extract_log <- tryCatch(
    utils::read.csv(extract_log_file, stringsAsFactors = FALSE),
    error = function(e) {
      warning(sprintf("Could not read existing extract log: %s", extract_log_file))
      NULL
    }
  )

  if (is.null(extract_log) || nrow(extract_log) == 0) {
    return(character(0))
  }

  required_cols <- c("tile", "status")
  if (!all(required_cols %in% names(extract_log))) {
    warning("Existing extract_log.csv does not contain both 'tile' and 'status'. No tiles will be skipped.")
    return(character(0))
  }

  unique(as.character(extract_log$tile[extract_log$status == "SUCCESS"]))
}

get_tiles_from_shapefiles <- function(shape_dir, shape_pattern, shape_prefix) {
  shape_files <- list.files(
    path = shape_dir,
    pattern = shape_pattern,
    full.names = FALSE
  )

  if (length(shape_files) == 0) {
    stop(sprintf(
      "No shapefiles matching pattern '%s' found in: %s",
      shape_pattern,
      shape_dir
    ), call. = FALSE)
  }

  tiles <- sub(paste0("^", shape_prefix), "", shape_files)
  tiles <- sub("\\.shp$", "", tiles, ignore.case = TRUE)

  unique(as.character(tiles[order(as.numeric(tiles))]))
}

build_raster_stack <- function(raster_dir, raster_pattern) {
  raster_files <- list.files(
    path = raster_dir,
    pattern = raster_pattern,
    full.names = TRUE
  )

  if (length(raster_files) == 0) {
    stop(sprintf("No raster files found in: %s", raster_dir), call. = FALSE)
  }

  rasters <- lapply(raster_files, raster::raster)
  raster::stack(rasters)
}

count_na_total <- function(df) {
  sum(is.na(df))
}

get_run_lengths <- function(x, target = TRUE) {
  r <- rle(x)
  lengths <- r$lengths[r$values == target]

  if (length(lengths) == 0) {
    return(integer(0))
  }

  lengths
}

get_leading_na_count <- function(x) {
  if (length(x) == 0 || !is.na(x[1])) {
    return(0L)
  }

  r <- rle(is.na(x))
  as.integer(r$lengths[1])
}

get_trailing_na_count <- function(x) {
  if (length(x) == 0 || !is.na(x[length(x)])) {
    return(0L)
  }

  r <- rle(is.na(x))
  as.integer(tail(r$lengths, 1))
}

build_pixel_na_qa <- function(value_df, filled_df, tile, point_ids = NULL) {
  raw_mat <- as.matrix(value_df)
  storage.mode(raw_mat) <- "numeric"

  filled_mat <- as.matrix(filled_df)
  storage.mode(filled_mat) <- "numeric"

  n_pixels <- nrow(raw_mat)
  n_observations <- ncol(raw_mat)

  if (is.null(point_ids)) {
    point_ids <- seq_len(n_pixels)
  }

  qa_rows <- lapply(seq_len(n_pixels), function(i) {
    raw_values <- raw_mat[i, ]
    filled_values <- filled_mat[i, ]

    raw_na <- is.na(raw_values)
    filled_na <- is.na(filled_values)

    na_before <- sum(raw_na)
    na_after <- sum(filled_na)
    nonmissing_before <- n_observations - na_before
    pct_missing_before <- if (n_observations > 0) na_before / n_observations else NA_real_

    na_runs <- get_run_lengths(raw_na, target = TRUE)
    valid_runs <- get_run_lengths(!raw_na, target = TRUE)

    leading_na <- get_leading_na_count(raw_values)
    trailing_na <- get_trailing_na_count(raw_values)
    max_na_gap <- if (length(na_runs) > 0) max(na_runs) else 0L
    max_valid_run <- if (length(valid_runs) > 0) max(valid_runs) else 0L

    all_missing <- na_before == n_observations
    any_missing <- na_before > 0
    has_internal_gap <- any_missing && !all_missing && (na_before > leading_na + trailing_na)

    data.frame(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      tile = tile,
      pointid = point_ids[i],
      n_observations = n_observations,
      n_nonmissing_before = nonmissing_before,
      na_before = na_before,
      na_after = na_after,
      na_filled = na_before - na_after,
      pct_missing_before = pct_missing_before,
      max_na_gap = max_na_gap,
      leading_na = leading_na,
      trailing_na = trailing_na,
      has_internal_gap = has_internal_gap,
      max_valid_run = max_valid_run,
      all_missing = all_missing,
      any_missing = any_missing,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, qa_rows)
}

build_tile_na_qa_summary <- function(pixel_qa_df, tile) {
  total_pixels <- nrow(pixel_qa_df)

  data.frame(
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    tile = tile,
    n_pixels = total_pixels,
    n_pixels_with_na = sum(pixel_qa_df$any_missing, na.rm = TRUE),
    n_pixels_all_missing = sum(pixel_qa_df$all_missing, na.rm = TRUE),
    n_pixels_with_internal_gap = sum(pixel_qa_df$has_internal_gap, na.rm = TRUE),
    total_na_before = sum(pixel_qa_df$na_before, na.rm = TRUE),
    total_na_after = sum(pixel_qa_df$na_after, na.rm = TRUE),
    total_na_filled = sum(pixel_qa_df$na_filled, na.rm = TRUE),
    mean_pct_missing_before = mean(pixel_qa_df$pct_missing_before, na.rm = TRUE),
    median_pct_missing_before = stats::median(pixel_qa_df$pct_missing_before, na.rm = TRUE),
    max_pct_missing_before = max(pixel_qa_df$pct_missing_before, na.rm = TRUE),
    max_na_gap = max(pixel_qa_df$max_na_gap, na.rm = TRUE),
    mean_max_na_gap = mean(pixel_qa_df$max_na_gap, na.rm = TRUE),
    pct_pixels_with_na = if (total_pixels > 0) sum(pixel_qa_df$any_missing, na.rm = TRUE) / total_pixels else NA_real_,
    pct_pixels_all_missing = if (total_pixels > 0) sum(pixel_qa_df$all_missing, na.rm = TRUE) / total_pixels else NA_real_,
    stringsAsFactors = FALSE
  )
}

fill_na_rows <- function(df) {
  mat <- as.matrix(df)
  storage.mode(mat) <- "numeric"

  filled <- t(zoo::na.approx(t(mat), na.rm = FALSE))
  filled <- t(zoo::na.locf(t(filled), na.rm = FALSE))
  filled <- t(zoo::na.locf(t(filled), fromLast = TRUE, na.rm = FALSE))

  as.data.frame(filled)
}

extract_values_for_tile <- function(tile,
                                    shape_dir,
                                    shape_prefix,
                                    rstack,
                                    raw_output_dir,
                                    include_pointid_column = TRUE,
                                    raw_output_suffix = ".csv") {
  start_time <- Sys.time()

  shp_name <- paste0(shape_prefix, tile)
  shape_file <- file.path(shape_dir, paste0(shp_name, ".shp"))
  output_file <- file.path(raw_output_dir, paste0(shp_name, raw_output_suffix))

  if (!file.exists(shape_file)) {
    stop(sprintf("Shapefile not found: %s", shape_file), call. = FALSE)
  }

  message(sprintf("Extracting %s ...", shp_name))

  tilepts <- sf::st_read(shape_file, quiet = TRUE)

  if (nrow(tilepts) == 0) {
    stop(sprintf("Shapefile contains no features: %s", shape_file), call. = FALSE)
  }

  if (include_pointid_column && !("pointid" %in% names(tilepts))) {
    stop(sprintf("Field 'pointid' not found in shapefile: %s", shape_file), call. = FALSE)
  }

  if (include_pointid_column && anyDuplicated(tilepts$pointid) > 0) {
    stop(sprintf("Field 'pointid' contains duplicate values in shapefile: %s", shape_file), call. = FALSE)
  }

  point_ids <- NULL
  if (include_pointid_column) {
    point_ids <- tilepts$pointid
  }

  tilepts_sp <- as(tilepts, "Spatial")
  ext <- raster::extract(rstack, tilepts_sp)

  if (is.null(ext) || nrow(ext) == 0) {
    stop(sprintf("No values extracted for shapefile: %s", shape_file), call. = FALSE)
  }

  ext_df <- as.data.frame(ext)

  if (include_pointid_column) {
    if (length(point_ids) != nrow(ext_df)) {
      stop(sprintf(
        "Mismatch between number of pointid values and extracted rows for shapefile: %s",
        shape_file
      ), call. = FALSE)
    }

    ext_df <- cbind(pointid = point_ids, ext_df)
  }

  utils::write.table(
    ext_df,
    file = output_file,
    sep = ",",
    row.names = FALSE,
    col.names = FALSE
  )

  elapsed <- as.numeric(Sys.time() - start_time, units = "secs")
  message(sprintf("Finished extraction for %s in %.2f seconds", shp_name, elapsed))

  list(
    data = ext_df,
    output_file = output_file,
    log_row = data.frame(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      tile = tile,
      shapefile = basename(shape_file),
      output_csv = basename(output_file),
      output_csv_path = normalizePath(output_file, winslash = "/", mustWork = FALSE),
      n_features = nrow(tilepts),
      n_rows_output = nrow(ext_df),
      pointid_included = include_pointid_column,
      status = "SUCCESS",
      message = NA_character_,
      elapsed_seconds = elapsed,
      stringsAsFactors = FALSE
    )
  )
}

fill_na_for_tile <- function(tile,
                             extracted_df,
                             fill_output_dir,
                             raw_output_dir,
                             shape_prefix,
                             raw_output_suffix = ".csv",
                             fill_output_suffix = "_fill.csv",
                             include_pointid_column = TRUE) {
  start_time <- Sys.time()

  shp_name <- paste0(shape_prefix, tile)
  output_file <- file.path(fill_output_dir, paste0(shp_name, fill_output_suffix))

  message(sprintf("Filling NAs for %s ...", shp_name))

  x <- extracted_df

  if (nrow(x) == 0) {
    stop(sprintf("Extracted data contains no rows for tile: %s", tile), call. = FALSE)
  }

  if (include_pointid_column) {
    if (!("pointid" %in% names(x))) {
      stop(sprintf("Column 'pointid' not found in extracted data for tile: %s", tile), call. = FALSE)
    }

    pointid_col <- x[, 1, drop = FALSE]
    value_df <- x[, -1, drop = FALSE]
  } else {
    pointid_col <- NULL
    value_df <- x
  }

  na_before <- count_na_total(value_df)
  filled_values <- fill_na_rows(value_df)
  na_after <- count_na_total(filled_values)

  pixel_ids <- if (include_pointid_column) pointid_col[[1]] else seq_len(nrow(value_df))

  pixel_qa <- build_pixel_na_qa(
    value_df = value_df,
    filled_df = filled_values,
    tile = tile,
    point_ids = pixel_ids
  )

  summary_qa <- build_tile_na_qa_summary(
    pixel_qa_df = pixel_qa,
    tile = tile
  )

  if (include_pointid_column) {
    output_df <- cbind(pointid_col, filled_values)
  } else {
    output_df <- filled_values
  }

  utils::write.table(
    output_df,
    file = output_file,
    row.names = FALSE,
    col.names = FALSE,
    sep = ","
  )

  elapsed <- as.numeric(Sys.time() - start_time, units = "secs")

  message(sprintf("NA count before fill: %d", na_before))
  message(sprintf("NA count after fill: %d", na_after))
  message(sprintf("Finished NA fill for %s in %.2f seconds", shp_name, elapsed))

  list(
    log_row = data.frame(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      tile = tile,
      input_file = paste0(shp_name, raw_output_suffix),
      input_file_path = normalizePath(file.path(raw_output_dir, paste0(shp_name, raw_output_suffix)), winslash = "/", mustWork = FALSE),
      output_file = basename(output_file),
      output_file_path = normalizePath(output_file, winslash = "/", mustWork = FALSE),
      n_rows = nrow(output_df),
      n_cols = ncol(output_df),
      na_before = na_before,
      na_after = na_after,
      pointid_preserved = include_pointid_column,
      status = "SUCCESS",
      message = NA_character_,
      elapsed_seconds = elapsed,
      stringsAsFactors = FALSE
    ),
    pixel_qa = pixel_qa,
    summary_qa = summary_qa
  )
}

#==============================#
# Main execution
#==============================#

stop_if_missing_dir(raster_dir, "Raster directory")
stop_if_missing_dir(shape_dir, "Shapefile directory")

dir.create(raw_output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fill_output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

tile_list <- get_tiles_from_shapefiles(
  shape_dir = shape_dir,
  shape_pattern = shape_pattern,
  shape_prefix = shape_prefix
)

message(sprintf(
  "Found %d tile shapefile(s) matching pattern '%s'.",
  length(tile_list),
  shape_pattern
))

completed_tiles <- get_completed_tiles(extract_log_file)

if (length(completed_tiles) > 0) {
  message(sprintf(
    "Found %d tile(s) already marked SUCCESS in extract_log.csv.",
    length(completed_tiles)
  ))
}

message("Building raster stack ...")
rstack <- build_raster_stack(raster_dir, raster_pattern)

extract_log_list <- list()
na_fill_log_list <- list()
na_fill_pixel_qa_log_list <- list()
na_fill_summary_qa_log_list <- list()

for (tile in tile_list) {

  tile_chr <- as.character(tile)

  if (tile_chr %in% completed_tiles) {
    message(sprintf(
      "Tile %s already successfully processed according to extract_log.csv. Skipping.",
      tile_chr
    ))
    next
  }

  extract_result <- tryCatch(
    {
      extract_values_for_tile(
        tile = tile_chr,
        shape_dir = shape_dir,
        shape_prefix = shape_prefix,
        rstack = rstack,
        raw_output_dir = raw_output_dir,
        include_pointid_column = include_pointid_column,
        raw_output_suffix = raw_output_suffix
      )
    },
    error = function(e) {
      shp_name <- paste0(shape_prefix, tile_chr)
      message(sprintf("ERROR during extraction for %s: %s", shp_name, e$message))

      list(
        data = NULL,
        output_file = file.path(raw_output_dir, paste0(shp_name, raw_output_suffix)),
        log_row = data.frame(
          timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
          tile = tile_chr,
          shapefile = paste0(shp_name, ".shp"),
          output_csv = paste0(shp_name, raw_output_suffix),
          output_csv_path = normalizePath(file.path(raw_output_dir, paste0(shp_name, raw_output_suffix)), winslash = "/", mustWork = FALSE),
          n_features = NA_integer_,
          n_rows_output = NA_integer_,
          pointid_included = include_pointid_column,
          status = "ERROR",
          message = e$message,
          elapsed_seconds = NA_real_,
          stringsAsFactors = FALSE
        )
      )
    }
  )

  extract_log_list[[length(extract_log_list) + 1]] <- extract_result$log_row

  if (!is.null(extract_result$data)) {
    na_fill_result <- tryCatch(
      {
        fill_na_for_tile(
          tile = tile_chr,
          extracted_df = extract_result$data,
          fill_output_dir = fill_output_dir,
          raw_output_dir = raw_output_dir,
          shape_prefix = shape_prefix,
          raw_output_suffix = raw_output_suffix,
          fill_output_suffix = fill_output_suffix,
          include_pointid_column = include_pointid_column
        )
      },
      error = function(e) {
        shp_name <- paste0(shape_prefix, tile_chr)
        message(sprintf("ERROR during NA fill for %s: %s", shp_name, e$message))

        list(
          log_row = data.frame(
            timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
            tile = tile_chr,
            input_file = paste0(shp_name, raw_output_suffix),
            input_file_path = normalizePath(file.path(raw_output_dir, paste0(shp_name, raw_output_suffix)), winslash = "/", mustWork = FALSE),
            output_file = paste0(shp_name, fill_output_suffix),
            output_file_path = normalizePath(file.path(fill_output_dir, paste0(shp_name, fill_output_suffix)), winslash = "/", mustWork = FALSE),
            n_rows = NA_integer_,
            n_cols = NA_integer_,
            na_before = NA_integer_,
            na_after = NA_integer_,
            pointid_preserved = include_pointid_column,
            status = "ERROR",
            message = e$message,
            elapsed_seconds = NA_real_,
            stringsAsFactors = FALSE
          ),
          pixel_qa = NULL,
          summary_qa = NULL
        )
      }
    )

    na_fill_log_list[[length(na_fill_log_list) + 1]] <- na_fill_result$log_row

    if (!is.null(na_fill_result$pixel_qa)) {
      na_fill_pixel_qa_log_list[[length(na_fill_pixel_qa_log_list) + 1]] <- na_fill_result$pixel_qa
    }

    if (!is.null(na_fill_result$summary_qa)) {
      na_fill_summary_qa_log_list[[length(na_fill_summary_qa_log_list) + 1]] <- na_fill_result$summary_qa
    }
  }
}

if (length(extract_log_list) > 0) {
  extract_log_df <- do.call(rbind, extract_log_list)
  append_log(extract_log_df, extract_log_file)
}

if (length(na_fill_log_list) > 0) {
  na_fill_log_df <- do.call(rbind, na_fill_log_list)
  append_log(na_fill_log_df, na_fill_log_file)
}

if (length(na_fill_pixel_qa_log_list) > 0) {
  na_fill_pixel_qa_log_df <- do.call(rbind, na_fill_pixel_qa_log_list)
  append_log(na_fill_pixel_qa_log_df, na_fill_pixel_qa_log_file)
}

if (length(na_fill_summary_qa_log_list) > 0) {
  na_fill_summary_qa_log_df <- do.call(rbind, na_fill_summary_qa_log_list)
  append_log(na_fill_summary_qa_log_df, na_fill_summary_qa_log_file)
}

message(sprintf("Extraction log written to: %s", extract_log_file))
message(sprintf("NA fill log written to: %s", na_fill_log_file))
message(sprintf("Pixel-level NA fill QA log written to: %s", na_fill_pixel_qa_log_file))
message(sprintf("Summary NA fill QA log written to: %s", na_fill_summary_qa_log_file))
message("All processing complete.")
