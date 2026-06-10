#--------------------------------------------------------------------------------------
# Name:         RScript_BFASTProgessMap.R
# Author:       Shawn Hutchinson
# Date Created: April 29, 2026
# Last Updated: April 29, 2026
#
# Description: Creates a shapefile that can show BFAST processing progress
#     1) Uses the log file Fishnet50K_processing_summary
#     2) Joins key information to the Fishnet50K feature class based on tile number
#
# Note:
#   - Run after producing an updated Master Processing Log
#--------------------------------------------------------------------------------------
library(sf)
library(dplyr)
library(readr)

summary_csv <- "D:/Research/Projects/BFAST_2001_2025/BFAST_H0.15/logs/Fishnet50K_processing_summary.csv"
fishnet_shp  <- "D:/Research/Projects/BFAST_2001_2025/BFAST_H0.15/logs/Fishnet50K.shp"

# Create timestamp
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")

# Output with timestamp
out_base <- paste0("D:/Research/Projects/BFAST_2001_2025/BFAST_H0.15/logs/Progress_", timestamp)
output_shp <- paste0(out_base, ".shp")

# Remove output if it somehow already exists (rare, but safe)
if (file.exists(output_shp)) {
  out_files <- paste0(out_base, c(".shp", ".shx", ".dbf", ".prj", ".cpg", ".qpj", ".sbn", ".sbx"))
  out_files <- out_files[file.exists(out_files)]
  file.remove(out_files)
}

summary <- read_csv(summary_csv)
fishnet <- st_read(fishnet_shp)

# Validate required fields
if (!"tile" %in% names(summary)) stop("CSV is missing field: tile")
if (!"completed_steps" %in% names(summary)) stop("CSV is missing field: completed_steps")
if (!"Tile" %in% names(fishnet)) stop("Fishnet shapefile is missing field: Tile")

# Join
fishnet_joined <- fishnet %>%
  mutate(Tile = as.integer(Tile)) %>%
  left_join(
    summary %>%
      transmute(
        Tile = as.integer(tile),
        comp_step = completed_steps
      ),
    by = "Tile"
  ) %>%
  mutate(
    comp_step = ifelse(is.na(comp_step), 0, comp_step)
  )

# Write shapefile
st_write(
  fishnet_joined,
  output_shp,
  driver = "ESRI Shapefile"
)
