# !/usr/bin/env python
# -*- coding: utf-8 -*-
#
# File name:    PythonScript_MosaicResultRasters.py
# Author:       Shawn Hutchinson
# Project:      BFAST grassland change analysis, 2001-2025
# Purpose:      Mosaic per-tile BFAST output rasters into larger output rasters
#               for selected fields, clean NoData values, and assign raster
#               attribute labels for categorical outputs.
#
# Inputs:
#   - Per-tile GeoTIFFs from PythonScript_CreateResultRasters.py
#   - MOD13Q1 template raster used for spatial reference, snap raster, extent,
#     and numeric cell size
#
# Outputs:
#   - Mosaic rasters written to output_folder as Mosaic_<FIELD>.tif
#   - Per-field processed logs: Mosaic_<FIELD>_processed.txt
#   - Run summary log: MosaicResultRasters_INTERP_QA_run_summary.csv
#
# Classification / trend metadata:
#   - Trend codes: -1 = Negative, 0 = Stable, 1 = Positive, -9999 = NoData
#   - Ecological class codes:
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
#       11 Other (valid BFAST combinations not assigned to classes 1-10)
#
# Notes:
#   - Update only the USER SETTINGS section for a new run.
#   - MosaicToNewRaster requires a numeric cell size; this script derives the
#     cell size from template_desc.meanCellWidth instead of passing a raster path.
#   - NoData is consistently represented as -9999 in tile rasters and cleaned to
#     true raster NoData in mosaics.
#   - Interpolation QA can be mosaicked as INTERP_PCT and INTERP_CLASS.
#   - INTERP_CLASS codes: 0 No interpolation, 1 Minor, 2 Moderate,
#     3 Excessive, 4 Severe, -9999 NoData.
#
# Date created: 2026-05-07
# Last updated: 2026-06-16
# Python version: 3.13.7
# Required software: ArcGIS Pro / ArcPy with Spatial Analyst

import arcpy
import os
import csv
from datetime import datetime

arcpy.env.overwriteOutput = True
arcpy.CheckOutExtension("Spatial")

# -----------------------------------------------------------------------------
# USER SETTINGS
# -----------------------------------------------------------------------------

input_folder = r"D:\Research\Projects\BFAST_2001_2025\BFAST_H0.15_Test\tile_results_rasters"
output_folder = r"D:\Research\Projects\BFAST_2001_2025\BFAST_H0.15_Test\mosaics"
log_folder = r"D:\Research\Projects\BFAST_2001_2025\BFAST_H0.15_Test\logs"
template_raster = r"D:\Research\Projects\BFAST_2001_2025\MOD13Q1\NDVI\MOD13Q1.061__250m_16_days_NDVI_doy2025353000000_aid0001.tif"

# Cycle through all output fields below.
value_fields = [
    "T_NBR",
    "T_SEASO",     # T_SEASON in result tiles
    "T_PERIO",     # T_PERIOD in result tiles
    "T_MAG",
    "T_SLOPE",
    "PVALUE",
    "TREND",
    "S_NBR",
    "S_SEASO",     # S_SEASON in result tiles
    "CLASS",
    "LABEL",
    "NOBS",
    "INTERP_P",    #INTERP_PCT
    "INTERP_C",    #INTERP_CLASS
    "T_CI_LOW",
    "T_CI_EST",
    "T_CI_UPP",
    "S_CI_LOW",
    "S_CI_EST",
    "S_CI_UPP",
]

# Optional: list any value fields to skip during this run.
# Leave this list empty to process all fields in value_fields.
# Example:
# omit_value_fields = ["T_CI_LOW", "T_CI_EST", "T_CI_UPP"]
omit_value_fields = [
    "T_NBR",
    "T_SEASO",     # T_SEASON in result tiles
    "T_PERIO",     # T_PERIOD in result tiles
    #"T_MAG",
    #"T_SLOPE",
    "PVALUE",
    "TREND",
    #"S_NBR",
    "S_SEASO",     # S_SEASON in result tiles
    "CLASS",
    "LABEL",
    #"NOBS",
    #"INTERP_P",    #INTERP_PCT
    #"INTERP_C",    #INTERP_CLASS
    "T_CI_LOW",
    "T_CI_EST",
    "T_CI_UPP",
    "S_CI_LOW",
    "S_CI_EST",
    "S_CI_UPP",
]

# Apply omit list while preserving the full value_fields list above as the menu
# of supported outputs. Matching is case-insensitive.
omit_value_fields = {field.upper() for field in omit_value_fields}
value_fields = [
    field for field in value_fields
    if field.upper() not in omit_value_fields
]

nodata_value = -9999
integer_fields = {
    "T_NBR",
    "T_SEASO",
    "T_PERIO",
    "TREND",
    "S_NBR",
    "S_SEASO",
    "CLASS",
    "LABEL",
    "NOBS",
    "INTERP_CLASS",
}

float_fields = {
    "T_MAG",
    "T_SLOPE",
    "PVALUE",
    "T_CI_LOW",
    "T_CI_EST",
    "T_CI_UPP",
    "S_CI_LOW",
    "S_CI_EST",
    "S_CI_UPP",
    "INTERP_PCT",
}

run_summary_log = os.path.join(log_folder, "MosaicResultRasters_INTERP_QA_run_summary.csv")

trend_labels = {
    -1: "Negative",
     0: "Stable",
     1: "Positive",
}

class_labels = {
    1: "Stable grassland",
    2: "Climate-driven variability",
    3: "Abrupt decline",
    4: "Recovery trajectory",
    5: "Sustained degradation",
    6: "Sustained improvement",
    7: "Phenological shift",
    8: "Highly dynamic",
    9: "Gradual decline",
    10: "Gradual improvement",
    11: "Other",
}

interp_labels = {
    0: "No interpolation",
    1: "Minor interpolation",
    2: "Moderate interpolation",
    3: "Excessive interpolation",
    4: "Severe interpolation",
}


def timestamp():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def field_exists(dataset, field_name):
    return field_name.upper() in [field.name.upper() for field in arcpy.ListFields(dataset)]


def read_processed_log(log_path):
    if not os.path.exists(log_path):
        return set()

    with open(log_path, "r", encoding="utf-8") as f:
        return set(line.strip() for line in f if line.strip())


def append_processed_log(log_path, raster_names):
    with open(log_path, "a", encoding="utf-8") as f:
        for raster_name in raster_names:
            f.write(raster_name + "\n")


def append_csv_log(csv_path, row, fieldnames):
    write_header = not os.path.exists(csv_path)

    with open(csv_path, "a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        if write_header:
            writer.writeheader()
        writer.writerow(row)


def log_result(value_field, mosaic_name, new_count, total_count, status, message=""):
    fieldnames = [
        "timestamp",
        "value_field",
        "mosaic_raster",
        "new_rasters_added",
        "total_input_rasters",
        "status",
        "message",
    ]

    append_csv_log(
        run_summary_log,
        {
            "timestamp": timestamp(),
            "value_field": value_field,
            "mosaic_raster": mosaic_name,
            "new_rasters_added": new_count,
            "total_input_rasters": total_count,
            "status": status,
            "message": message,
        },
        fieldnames,
    )


def clean_nodata_and_label_mosaic(mosaic_path, value_field):
    vf = value_field.upper()

    if not arcpy.Exists(mosaic_path):
        return "mosaic does not exist"

    print(f"Cleaning NoData for {vf} mosaic...")

    temp_clean = os.path.join("in_memory", f"temp_clean_{vf}")

    clean_raster = arcpy.sa.SetNull(
        arcpy.sa.Raster(mosaic_path) == nodata_value,
        arcpy.sa.Raster(mosaic_path),
    )

    if vf in integer_fields:
        clean_raster = arcpy.sa.Int(clean_raster)

    clean_raster.save(temp_clean)
    arcpy.management.CopyRaster(temp_clean, mosaic_path)
    arcpy.management.Delete(temp_clean)

    if vf not in {"TREND", "CLASS", "LABEL", "INTERP_CLASS"}:
        return "cleaned nodata"

    print(f"Building raster attribute table and labels for {vf} mosaic...")

    arcpy.management.BuildRasterAttributeTable(mosaic_path, "Overwrite")

    if vf == "INTERP_CLASS":
        label_field = "INTERPCLS"
        label_length = 40
    else:
        label_field = "CLASSLABEL" if vf in {"CLASS", "LABEL"} else "TRENDCLS"
        label_length = 80 if vf in {"CLASS", "LABEL"} else 20

    if not field_exists(mosaic_path, label_field):
        arcpy.management.AddField(mosaic_path, label_field, "TEXT", field_length=label_length)

    if vf == "INTERP_CLASS":
        labels = interp_labels
    else:
        labels = class_labels if vf in {"CLASS", "LABEL"} else trend_labels

    with arcpy.da.UpdateCursor(mosaic_path, ["VALUE", label_field]) as cursor:
        for row in cursor:
            try:
                key = int(row[0])
            except (TypeError, ValueError):
                key = None
            row[1] = labels.get(key, "NoData" if key == nodata_value else "Other")
            cursor.updateRow(row)

    return "cleaned nodata and labeled"


# -----------------------------------------------------------------------------
# MAIN EXECUTION
# -----------------------------------------------------------------------------

if not os.path.exists(output_folder):
    os.makedirs(output_folder)

if not os.path.exists(log_folder):
    os.makedirs(log_folder)

template_desc = arcpy.Describe(template_raster)

# MosaicToNewRaster requires a numeric cell size.
# Do not pass arcpy.env.cellSize when it has been set to a raster path/object.
template_cell_size = float(template_desc.meanCellWidth)

arcpy.env.outputCoordinateSystem = template_desc.spatialReference
arcpy.env.snapRaster = template_raster
arcpy.env.cellSize = template_cell_size
arcpy.env.extent = template_raster

print(f"Reading tile rasters from: {input_folder}")
print(f"Writing mosaics to: {output_folder}")
print(f"Writing logs to: {log_folder}")
print(f"Using template cell size: {template_cell_size}")
print(f"Processing value fields: {', '.join(value_fields)}")
if omit_value_fields:
    print(f"Omitted value fields: {', '.join(sorted(omit_value_fields))}")

for value_field in value_fields:
    vf = value_field.upper()
    mosaic_name = f"Mosaic_{vf}.tif"
    mosaic_path = os.path.join(output_folder, mosaic_name)
    processed_log = os.path.join(log_folder, f"Mosaic_{vf}_processed.txt")

    pixel_type = "32_BIT_FLOAT" if vf in float_fields else "16_BIT_SIGNED"

    print("=" * 80)
    print(f"Mosaicking {vf}")
    print(f"Processed log: {processed_log}")
    print("=" * 80)

    processed_files = read_processed_log(processed_log)

    all_rasters = [
        f for f in os.listdir(input_folder)
        if f.lower().endswith(".tif") and f.lower().endswith(f"_{vf.lower()}.tif")
    ]

    new_raster_names = [f for f in all_rasters if f not in processed_files]
    new_rasters = [os.path.join(input_folder, f) for f in new_raster_names]

    try:
        if len(new_rasters) == 0:
            print(f"No new {vf} rasters found to mosaic.")
            clean_msg = clean_nodata_and_label_mosaic(mosaic_path, vf)
            log_result(vf, mosaic_name, 0, len(all_rasters), "NO_NEW_RASTERS", clean_msg)
        else:
            print(f"Found {len(new_rasters)} new {vf} rasters to mosaic.")

            if not arcpy.Exists(mosaic_path):
                print(f"Creating new mosaic: {mosaic_path}")

                arcpy.management.MosaicToNewRaster(
                    input_rasters=new_rasters,
                    output_location=output_folder,
                    raster_dataset_name_with_extension=mosaic_name,
                    coordinate_system_for_the_raster=template_desc.spatialReference,
                    pixel_type=pixel_type,
                    cellsize=template_cell_size,
                    number_of_bands=1,
                    mosaic_method="FIRST",
                    mosaic_colormap_mode="FIRST",
                )

                status = "CREATED"
            else:
                print(f"Updating existing mosaic: {mosaic_path}")

                arcpy.management.Mosaic(
                    inputs=new_rasters,
                    target=mosaic_path,
                    mosaic_type="FIRST",
                    colormap="FIRST",
                )

                status = "UPDATED"

            append_processed_log(processed_log, new_raster_names)
            clean_msg = clean_nodata_and_label_mosaic(mosaic_path, vf)
            log_result(vf, mosaic_name, len(new_rasters), len(all_rasters), status, clean_msg)

        print(f"Mosaic operation complete for {vf}!")
        print(f"Mosaic raster: {mosaic_path}")
        print(f"New rasters added this run: {len(new_rasters)}")
        print(f"Total {vf} rasters available for mosaicking: {len(all_rasters)}")
        print(f"Log file: {processed_log}")

    except Exception as e:
        msg = str(e)
        print(f"ERROR mosaicking {vf}: {msg}")
        log_result(vf, mosaic_name, len(new_rasters), len(all_rasters), "ERROR", msg)

print("Mosaic operation complete for all requested output fields!")
print(f"Run summary log: {run_summary_log}")
