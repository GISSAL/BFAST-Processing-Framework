#--------------------------------------------------------------------------------------
# Name:         RScript_Cleanup_Extract_and_Results.R
# Description:
#   Cleanup options:
#     1) Delete raw extract files if corresponding _fill file exists
#     2) Delete *_unmatched.csv files
#     3) Run both cleanup operations
#--------------------------------------------------------------------------------------

extract_dir <- "D:/Research/Projects/BFAST_2001_2025/BFAST/filled"
results_dir <- "D:/Research/Projects/BFAST_2001_2025/BFAST_H0.15_Test/tile_results"

prefix <- "Centroids_"
fill_suffix <- "_fill.csv"

dry_run <- FALSE

#==============================#
# Select cleanup mode
#==============================#

choice <- menu(
  choices = c(
    "raw_only       - delete Centroids_XXX.csv if _fill exists",
    "unmatched_only - delete *_unmatched.csv files",
    "both           - run both cleanup operations"
  ),
  title = "Select cleanup mode:"
)

if (choice == 0) {
  stop("No cleanup mode selected. Script cancelled.", call. = FALSE)
}

cleanup_mode <- c("raw_only", "unmatched_only", "both")[choice]

cat("\nSelected cleanup mode:", cleanup_mode, "\n")
cat("Dry run:", dry_run, "\n\n")

#==============================#
# Helper functions
#==============================#

delete_or_preview <- function(path, label) {
  if (dry_run) {
    message(sprintf("[DRY RUN] Would delete %s: %s", label, basename(path)))
    return(FALSE)
  }

  deleted <- file.remove(path)

  if (isTRUE(deleted)) {
    message(sprintf("Deleted %s: %s", label, basename(path)))
  } else {
    warning(sprintf("Failed to delete %s: %s", label, path))
  }

  isTRUE(deleted)
}

cleanup_raw_extracts <- function() {
  if (!dir.exists(extract_dir)) {
    stop(sprintf("Extract directory does not exist: %s", extract_dir), call. = FALSE)
  }

  raw_files <- list.files(
    extract_dir,
    pattern = paste0("^", prefix, "[0-9]+\\.csv$"),
    full.names = FALSE
  )

  message(sprintf("Found %d raw candidate file(s).", length(raw_files)))

  deleted_count <- 0

  for (raw_file in raw_files) {
    tile <- sub(paste0("^", prefix), "", raw_file)
    tile <- sub("\\.csv$", "", tile)

    fill_file <- paste0(prefix, tile, fill_suffix)

    raw_path <- file.path(extract_dir, raw_file)
    fill_path <- file.path(extract_dir, fill_file)

    if (file.exists(fill_path)) {
      if (delete_or_preview(raw_path, "raw file")) {
        deleted_count <- deleted_count + 1
      }
    }
  }

  deleted_count
}

cleanup_unmatched_files <- function() {
  if (!dir.exists(results_dir)) {
    stop(sprintf("Results directory does not exist: %s", results_dir), call. = FALSE)
  }

  unmatched_files <- list.files(
    results_dir,
    pattern = "_unmatched\\.csv$",
    full.names = TRUE
  )

  message(sprintf("Found %d unmatched file(s).", length(unmatched_files)))

  deleted_count <- 0

  for (f in unmatched_files) {
    if (delete_or_preview(f, "unmatched file")) {
      deleted_count <- deleted_count + 1
    }
  }

  deleted_count
}

#==============================#
# Run selected cleanup
#==============================#

deleted_raw_count <- 0
deleted_unmatched_count <- 0

if (cleanup_mode %in% c("raw_only", "both")) {
  deleted_raw_count <- cleanup_raw_extracts()
}

if (cleanup_mode %in% c("unmatched_only", "both")) {
  deleted_unmatched_count <- cleanup_unmatched_files()
}

message("Cleanup complete:")
message(sprintf("  Mode: %s", cleanup_mode))
message(sprintf("  Dry run: %s", dry_run))
message(sprintf("  Raw files deleted: %d", deleted_raw_count))
message(sprintf("  Unmatched files deleted: %d", deleted_unmatched_count))
