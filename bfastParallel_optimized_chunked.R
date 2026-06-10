#--------------------------------------------------------------------------------------
# Name:         bfastParallel_optimized_chunked.R
# Author:       Shawn Hutchinson / revised with ChatGPT assistance
# Date Created: September 20, 2008
# Last Updated: June 4, 2026
#
# Purpose:
#   Runs BFAST analysis on time-series centroid data using optimized parallel
#   processing, reduced disk I/O, and chunked dynamic scheduling.
#
# Key performance changes from bfastParallel_optimized.R:
#   - Uses chunked dynamic scheduling instead of scheduling one row at a time
#   - Avoids repeated as.numeric() conversion inside each pixel call
#   - Precomputes valid observation counts once before parallel processing
#   - Optionally skips confidence interval calculations, which can be expensive
#   - Builds all output line vectors in one pass through the result list
#   - Writes each output file once
#
# Usage:
#   Rscript bfastParallel_optimized_chunked.R <number_of_cores> <input_csv> [chunk_size]
#
# Optional:
#   chunk_size defaults to 100 rows per scheduled task.
#   Increase if scheduling overhead is high and pixel runtimes are similar.
#   Decrease if pixel runtimes are highly uneven.
#--------------------------------------------------------------------------------------

library("bfast")
library("parallel")
library("data.table")

# -----------------------------------------------------------------------------
# User settings
# -----------------------------------------------------------------------------

annual_image_frequency <- 23
tsdata_start_year <- 2001

# Suggested h values: "rdist" or 0.15
# bfast_h <- 0.15
bfast_h <- "rdist"

# Options include: "harmonic", "dummy", or "none"
bfast_season <- "harmonic"

# Suggested max.iter value: 1
bfast_max_iter <- 1

# Confidence intervals can be expensive. Set TRUE only if these outputs are needed.
calculate_confint <- FALSE

# Output folder.
output_dir <- "Output2"

# Default number of rows assigned to each scheduled parallel task.
default_chunk_size <- 1000

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------

makeCsvLine <- function(values) {
  paste(values, collapse = ",")
}

flattenBreakConfint <- function(break_object) {
  tryCatch(
    {
      if (is.null(break_object)) {
        NA
      } else {
        confint_object <- confint(break_object)

        if (!is.null(confint_object$confint)) {
          as.vector(t(as.matrix(confint_object$confint)))
        } else {
          as.vector(t(as.matrix(confint_object)))
        }
      }
    },
    error = function(e) NA
  )
}

emptyPixelResult <- function(poly_id, ndvi_length, valid_observation_count) {
  list(
    trend_breaks_time = c(poly_id, NA),
    trend_breaks_magnitude = c(poly_id, NA),
    trend_nbbreaks = c(poly_id, NA),
    trend_bfast = c(poly_id, rep(NA, ndvi_length)),
    season_nbbreaks = c(poly_id, NA),
    season_breaks_time = c(poly_id, NA),
    season_bfast = c(poly_id, rep(NA, ndvi_length)),
    trend_breaks_confint = c(poly_id, NA),
    season_breaks_confint = c(poly_id, NA),
    residuals_bfast = c(poly_id, rep(NA, ndvi_length)),
    nobs = c(poly_id, valid_observation_count)
  )
}

makeRowChunks <- function(arr, chunk_size) {
  split(arr, ceiling(seq_along(arr) / chunk_size))
}

makeOutputPaths <- function(tileName, output_dir) {
  list(
    trend_breaks_time = paste0(output_dir, "/", tileName, "_trend_breaks_time.txt"),
    trend_breaks_magnitude = paste0(output_dir, "/", tileName, "_trend_breaks_magnitude.txt"),
    trend_nbbreaks = paste0(output_dir, "/", tileName, "_trend_nbbreaks.txt"),
    trend_bfast = paste0(output_dir, "/", tileName, "_trend_bfast.txt"),
    season_nbbreaks = paste0(output_dir, "/", tileName, "_season_nbbreaks.txt"),
    season_breaks_time = paste0(output_dir, "/", tileName, "_season_breaks_time.txt"),
    season_bfast = paste0(output_dir, "/", tileName, "_season_bfast.txt"),
    trend_breaks_confint = paste0(output_dir, "/", tileName, "_trend_breaks_confint.txt"),
    season_breaks_confint = paste0(output_dir, "/", tileName, "_season_breaks_confint.txt"),
    residuals_bfast = paste0(output_dir, "/", tileName, "_residuals_bfast.txt"),
    nobs = paste0(output_dir, "/", tileName, "_nobs.txt")
  )
}

writeOutputLines <- function(output_lines, output_paths) {
  for (result_name in names(output_paths)) {
    fwrite(
      data.table(line = output_lines[[result_name]]),
      file = output_paths[[result_name]],
      col.names = FALSE,
      quote = FALSE
    )
  }
}

buildOutputLines <- function(results, result_names) {
  output_lines <- setNames(
    vector("list", length(result_names)),
    result_names
  )

  for (result_name in result_names) {
    output_lines[[result_name]] <- character(length(results))
  }

  for (i in seq_along(results)) {
    result <- results[[i]]

    for (result_name in result_names) {
      if (!is.list(result) || is.null(result[[result_name]])) {
        warning(
          "Malformed result at results[[", i, "]] for output '",
          result_name,
          "'. Writing NA placeholder."
        )
        output_lines[[result_name]][i] <- makeCsvLine(c(NA, NA))
      } else {
        output_lines[[result_name]][i] <- makeCsvLine(result[[result_name]])
      }
    }
  }

  output_lines
}

# -----------------------------------------------------------------------------
# Function run through the parallel process
# -----------------------------------------------------------------------------

bfastPixel <- function(count) {
  poly_id <- poly_ids[count]

  # tpdata is already a double matrix, so avoid repeated as.numeric() conversion.
  ndvi <- tpdata[count, ]
  valid_observation_count <- valid_observation_counts[count]

  tryCatch({
    tsdata <- ts(
      ndvi,
      frequency = annual_image_frequency,
      start = c(tsdata_start_year, 1)
    )
    dim(tsdata) <- NULL

    fits <- bfast(
      tsdata,
      h = h_value,
      season = bfast_season,
      max.iter = bfast_max_iter
    )

    fits_output <- fits$output[[1]]

    trend_break_time <- fits$Time[1]
    trend_break_magnitude <- fits$Magnitude[1]
    trend_nbbreak <- NROW(fits_output$Vt.bp)
    trend_bfast <- as.vector(fits_output$Tt)

    season_nbbreak <- NROW(fits_output$Wt.bp)
    season_breaks_time <- as.vector(fits_output$Wt.bp)
    season_bfast <- as.vector(fits_output$St)
    residuals_bfast <- as.vector(fits_output$Nt)

    if (calculate_confint) {
      trend_break_confint <- flattenBreakConfint(fits_output$Vt.bp)
      season_break_confint <- flattenBreakConfint(fits_output$Wt.bp)
    } else {
      trend_break_confint <- NA
      season_break_confint <- NA
    }

    list(
      trend_breaks_time = c(poly_id, trend_break_time),
      trend_breaks_magnitude = c(poly_id, trend_break_magnitude),
      trend_nbbreaks = c(poly_id, trend_nbbreak),
      trend_bfast = c(poly_id, trend_bfast),
      season_nbbreaks = c(poly_id, season_nbbreak),
      season_breaks_time = c(poly_id, season_breaks_time),
      season_bfast = c(poly_id, season_bfast),
      trend_breaks_confint = c(poly_id, trend_break_confint),
      season_breaks_confint = c(poly_id, season_break_confint),
      residuals_bfast = c(poly_id, residuals_bfast),
      nobs = c(poly_id, valid_observation_count)
    )
  }, error = function(e) {
    message(
      "BFAST failed for row ", count,
      ", poly_id ", poly_id,
      ": ", conditionMessage(e)
    )
    emptyPixelResult(poly_id, length(ndvi), valid_observation_count)
  })
}

bfastChunk <- function(rows) {
  lapply(rows, bfastPixel)
}

# -----------------------------------------------------------------------------
# Main script
# -----------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 2) {
  stop("Usage: Rscript bfastParallel_optimized_chunked.R <number_of_cores> <input_csv> [chunk_size]")
}

no_cores <- suppressWarnings(strtoi(args[1]))
if (is.na(no_cores) || no_cores < 1) {
  stop("Invalid number_of_cores: ", args[1])
}

filename <- args[2]
if (!file.exists(filename)) {
  stop("Input file does not exist: ", filename)
}

chunk_size <- default_chunk_size
if (length(args) >= 3) {
  chunk_size_arg <- suppressWarnings(strtoi(args[3]))
  if (!is.na(chunk_size_arg) && chunk_size_arg >= 1) {
    chunk_size <- chunk_size_arg
  } else {
    warning("Invalid chunk_size '", args[3], "'. Using default chunk_size = ", default_chunk_size)
  }
}

message("Using cores: ", no_cores)
message("Input file: ", filename)
message("Chunk size: ", chunk_size)
message("Calculate confidence intervals: ", calculate_confint)

tileName <- strsplit(filename, "_")[[1]][2]

inidata <- fread(
  filename,
  header = FALSE,
  sep = ",",
  dec = ".",
  na.strings = c("NA", "NaN", "", "NULL", "null")
)

if (nrow(inidata) < 1) {
  stop("Input file has zero rows: ", filename)
}

if (ncol(inidata) < 2) {
  stop("Input file must have at least 2 columns: ID + time-series values")
}

poly_ids <- inidata[[1]]
ndvi_data <- as.data.frame(inidata[, 2:ncol(inidata), with = FALSE])

na_before_conversion <- sum(is.na(ndvi_data))

ndvi_data[] <- lapply(ndvi_data, function(x) {
  suppressWarnings(as.numeric(x))
})

na_after_conversion <- sum(is.na(ndvi_data))
new_na_count <- na_after_conversion - na_before_conversion

if (new_na_count > 0) {
  warning(
    new_na_count,
    " time-series value(s) could not be converted to numeric and were set to NA."
  )
}

bad_cols <- which(vapply(ndvi_data, function(x) all(is.na(x)), logical(1)))
if (length(bad_cols) > 0) {
  warning(
    "Some time-series columns converted entirely to NA. Original input column(s): ",
    paste(bad_cols + 1, collapse = ", ")
  )
}

tpdata <- as.matrix(ndvi_data)
storage.mode(tpdata) <- "double"
vmax <- dim(tpdata)

message("Input rows: ", vmax[1])
message("Input ID columns: 1")
message("Input numeric time-series columns: ", vmax[2])

# Precompute constants used by each pixel.
rdist <- annual_image_frequency / vmax[2]
h_value <- if (identical(bfast_h, "rdist")) rdist else bfast_h

# Precompute observation counts once instead of inside every worker call.
valid_observation_counts <- rowSums(!is.na(tpdata))

arr <- seq_len(vmax[1])
row_chunks <- makeRowChunks(arr, chunk_size)

message("Scheduled chunks: ", length(row_chunks))
message("Approximate rows per chunk: ", chunk_size)

# Chunked dynamic scheduling:
#   - mc.preschedule = FALSE keeps load balancing across chunks.
#   - Each scheduled task contains many rows, reducing scheduler overhead.
chunk_results <- mclapply(
  row_chunks,
  bfastChunk,
  mc.cores = no_cores,
  mc.preschedule = FALSE
)

results <- unlist(chunk_results, recursive = FALSE)

# Write each output file once.
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
output_paths <- makeOutputPaths(tileName, output_dir)
output_lines <- buildOutputLines(results, names(output_paths))
writeOutputLines(output_lines, output_paths)

message("Finished BFAST processing for tile ", tileName)

rm(list = ls())
