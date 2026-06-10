# !/usr/bin/env python
# -*- coding: utf-8 -*-

#    File name: PythonScript_CreateResultRasters_ALL_OUTPUTS_WITH_LOGS.py
#    Author: Shawn Hutchinson
#    Description: Converts result tiles into raster TIFs for all requested BFAST output fields
#                 and writes per-field processed logs plus a run summary CSV.
#    Date created: 05/07/2026
#    Date updated: 05/09/2026
#    Python Version: 3.13.7
#    Note:  Includes an omit_value_fields list to selectively skip certain output fields.

import arcpy
import os
import re
import csv
from datetime import datetime

arcpy.env.overwriteOutput = True

# -----------------------------------------------------------------------------
# USER SETTINGS
# -----------------------------------------------------------------------------

input_folder = r"D:\Research\Projects\BFAST_2001_2025\BFAST_H0.15\tile_results"
output_folder = r"D:\Research\Projects\BFAST_2001_2025\BFAST_H0.15\tile_results_rasters"
template_raster = r"D:\Research\Projects\BFAST_2001_2025\BFAST_Analysis\BFAST_Analysis.gdb\MOD13Q1_061_NDVI_DOY2025193"

# User-defined log folder
log_folder = r"D:\Research\Projects\BFAST_2001_2025\BFAST_H0.15\logs"

if not os.path.exists(output_folder):
    os.makedirs(output_folder)

if not os.path.exists(log_folder):
    os.makedirs(log_folder)

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
    # "T_NBR",
    "T_SEASO",
    "T_PERIO",
    "T_MAG",
    "T_SLOPE",
    "PVALUE",
    # "TREND",
    "S_NBR",
    "S_SEASO",
    "CLASS",
    # "LABEL",
    "NOBS",
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

trend_value_field = "TRENDVAL"
class_value_field = "CLASSVAL"
nodata_value = -9999

run_summary_log = os.path.join(log_folder, "CreateResultRasters_ALL_OUTPUTS_run_summary.csv")

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
}

class_lookup = {
    "STABLE GRASSLAND": 1,
    "INTERANNUAL CLIMATE VARIABILITY": 2,
    "ABRUPT PRODUCTIVITY DECLINE": 3,
    "RECOVERY / RESILIENCE": 4,
    "PERSISTENT DECLINE": 5,
    "CHRONIC DEGRADATION": 5,  # accepted legacy label
    "PERSISTENT IMPROVEMENT": 6,
    "PHENOLOGICAL SHIFT": 7,
    "HIGHLY DYNAMIC / UNSTABLE": 8,
}

class_labels = {
    1: "Stable grassland",
    2: "Interannual climate variability",
    3: "Abrupt productivity decline",
    4: "Recovery / resilience",
    5: "Persistent decline",
    6: "Persistent improvement",
    7: "Phenological shift",
    8: "Highly dynamic / unstable",
}

trend_labels = {
    -1: "Negative",
     0: "Stable",
     1: "Positive",
}


def timestamp():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def safe_memory_name(name):
    """Create a short ArcGIS-safe in_memory dataset name."""
    clean = re.sub(r"[^A-Za-z0-9_]", "_", name)
    return clean[:60]


def field_exists(dataset, field_name):
    return field_name.upper() in [field.name.upper() for field in arcpy.ListFields(dataset)]


def add_field_if_missing(dataset, field_name, field_type):
    if not field_exists(dataset, field_name):
        arcpy.management.AddField(dataset, field_name, field_type)


def read_processed_log(log_path):
    if not os.path.exists(log_path):
        return set()

    with open(log_path, "r", encoding="utf-8") as f:
        return set(line.strip() for line in f if line.strip())


def append_processed_log(log_path, raster_name):
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(raster_name + "\n")


def append_csv_log(csv_path, row, fieldnames):
    write_header = not os.path.exists(csv_path)

    with open(csv_path, "a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        if write_header:
            writer.writeheader()
        writer.writerow(row)


def log_result(value_field, shp_name, raster_name, status, message=""):
    fieldnames = [
        "timestamp",
        "value_field",
        "input_shapefile",
        "output_raster",
        "status",
        "message",
    ]

    append_csv_log(
        run_summary_log,
        {
            "timestamp": timestamp(),
            "value_field": value_field,
            "input_shapefile": shp_name,
            "output_raster": raster_name,
            "status": status,
            "message": message,
        },
        fieldnames,
    )


def prepare_trend_value_field(shp_path, source_field):
    add_field_if_missing(shp_path, trend_value_field, "SHORT")
    bad_values = set()

    with arcpy.da.UpdateCursor(shp_path, [source_field, trend_value_field]) as cursor:
        for row in cursor:
            raw_value = row[0]

            if raw_value is None:
                row[1] = nodata_value
                bad_values.add("NULL")
            else:
                trend_text = str(raw_value).strip().upper()

                if "NEGATIVE" in trend_text:
                    row[1] = -1
                elif "STABLE" in trend_text:
                    row[1] = 0
                elif "POSITIVE" in trend_text:
                    row[1] = 1
                else:
                    row[1] = nodata_value
                    bad_values.add(repr(raw_value))

            cursor.updateRow(row)

    return trend_value_field, bad_values


def prepare_class_value_field(shp_path, source_field):
    add_field_if_missing(shp_path, class_value_field, "SHORT")
    bad_values = set()

    with arcpy.da.UpdateCursor(shp_path, [source_field, class_value_field]) as cursor:
        for row in cursor:
            raw_value = row[0]

            if raw_value is None:
                row[1] = nodata_value
                bad_values.add("NULL")
            else:
                class_text = str(raw_value).strip()

                try:
                    numeric_class = int(float(class_text))
                except ValueError:
                    numeric_class = None

                if numeric_class is not None and 1 <= numeric_class <= 8:
                    row[1] = numeric_class
                else:
                    normalized_class = " ".join(class_text.upper().split())

                    if normalized_class in class_lookup:
                        row[1] = class_lookup[normalized_class]
                    else:
                        row[1] = nodata_value
                        bad_values.add(repr(raw_value))

            cursor.updateRow(row)

    return class_value_field, bad_values


def add_raster_labels(raster_path, value_field):
    """Build a raster attribute table and add label text for categorical outputs."""
    vf = value_field.upper()

    if vf not in {"TREND", "CLASS", "LABEL"}:
        return

    arcpy.management.BuildRasterAttributeTable(raster_path, "Overwrite")

    label_field = "CLASSLABEL" if vf in {"CLASS", "LABEL"} else "TRENDCLS"
    label_length = 80 if vf in {"CLASS", "LABEL"} else 20

    if not field_exists(raster_path, label_field):
        arcpy.management.AddField(raster_path, label_field, "TEXT", field_length=label_length)

    labels = class_labels if vf in {"CLASS", "LABEL"} else trend_labels

    with arcpy.da.UpdateCursor(raster_path, ["VALUE", label_field]) as cursor:
        for row in cursor:
            try:
                key = int(row[0])
            except (TypeError, ValueError):
                key = None
            row[1] = labels.get(key, "NoData" if key == nodata_value else "Other")
            cursor.updateRow(row)


# -----------------------------------------------------------------------------
# MAIN EXECUTION
# -----------------------------------------------------------------------------

if not os.path.exists(output_folder):
    os.makedirs(output_folder)

if not os.path.exists(log_folder):
    os.makedirs(log_folder)

arcpy.env.snapRaster = template_raster
arcpy.env.cellSize = template_raster
arcpy.env.outputCoordinateSystem = arcpy.Describe(template_raster).spatialReference

arcpy.CheckOutExtension("Spatial")

arcpy.env.workspace = input_folder
shapefiles = arcpy.ListFeatureClasses("*.shp") or []

print(f"Found {len(shapefiles)} shapefile(s) in {input_folder}")
print(f"Writing rasters to: {output_folder}")
print(f"Writing logs to: {log_folder}")
print(f"Processing value fields: {', '.join(value_fields)}")
if omit_value_fields:
    print(f"Omitted value fields: {', '.join(sorted(omit_value_fields))}")

for value_field in value_fields:
    vf = value_field.upper()
    processed_log = os.path.join(log_folder, f"CreateResultRasters_{vf}_processed.txt")
    processed_files = read_processed_log(processed_log)

    print("=" * 80)
    print(f"Creating rasters for {vf}")
    print(f"Processed log: {processed_log}")
    print("=" * 80)

    created_count = 0
    skipped_count = 0
    error_count = 0

    for shp in shapefiles:
        shp_path = os.path.join(input_folder, shp)
        base_name = os.path.splitext(shp)[0]

        raster_field = value_field
        out_raster_name = f"{base_name}_{vf}.tif"
        out_raster = os.path.join(output_folder, out_raster_name)

        try:
            if out_raster_name in processed_files and arcpy.Exists(out_raster):
                msg = "already listed in processed log and raster exists"
                print(f"Skipping {base_name} {vf}: {msg}")
                skipped_count += 1
                log_result(vf, shp, out_raster_name, "SKIPPED", msg)
                continue

            if arcpy.Exists(out_raster):
                msg = "raster already exists"
                print(f"Skipping {base_name} {vf}: {msg}")
                skipped_count += 1
                log_result(vf, shp, out_raster_name, "SKIPPED", msg)
                continue

            if not field_exists(shp_path, value_field):
                msg = f"field '{value_field}' not found"
                print(f"Skipping {base_name} {vf}: {msg}")
                skipped_count += 1
                log_result(vf, shp, out_raster_name, "SKIPPED", msg)
                continue

            if int(arcpy.management.GetCount(shp_path)[0]) == 0:
                msg = "no points found"
                print(f"Skipping {base_name} {vf}: {msg}")
                skipped_count += 1
                log_result(vf, shp, out_raster_name, "SKIPPED", msg)
                continue

            if vf == "TREND":
                raster_field, bad_values = prepare_trend_value_field(shp_path, value_field)
                if bad_values:
                    print(f"Warning for {base_name}: unexpected TREND values found: {sorted(bad_values)}")

            elif vf in {"CLASS", "LABEL"}:
                raster_field, bad_values = prepare_class_value_field(shp_path, value_field)
                if bad_values:
                    print(f"Warning for {base_name}: unexpected {vf} values found: {sorted(bad_values)}")

            print(f"Converting {base_name} using field '{raster_field}' for output '{vf}'...")

            temp_raster = os.path.join("in_memory", safe_memory_name(f"tmp_{base_name}_{vf}"))

            arcpy.conversion.PointToRaster(
                in_features=shp_path,
                value_field=raster_field,
                out_rasterdataset=temp_raster,
                cell_assignment="MAXIMUM",
                priority_field="NONE",
                cellsize=arcpy.env.cellSize,
            )

            raster_obj = arcpy.sa.Con(
                arcpy.sa.IsNull(temp_raster),
                nodata_value,
                temp_raster,
            )

            if vf in integer_fields:
                raster_obj = arcpy.sa.Int(raster_obj)

            raster_obj.save(out_raster)

            arcpy.management.SetRasterProperties(
                in_raster=out_raster,
                nodata=f"1 {nodata_value}",
            )

            add_raster_labels(out_raster, vf)
            arcpy.management.Delete(temp_raster)

            append_processed_log(processed_log, out_raster_name)
            processed_files.add(out_raster_name)

            created_count += 1
            log_result(vf, shp, out_raster_name, "SUCCESS", "created")
            print(f"Created {out_raster}")

        except Exception as e:
            error_count += 1
            msg = str(e)
            print(f"ERROR creating {out_raster_name}: {msg}")
            log_result(vf, shp, out_raster_name, "ERROR", msg)

    rasters = [
        f for f in os.listdir(output_folder)
        if f.lower().endswith(".tif") and f.lower().endswith(f"_{vf.lower()}.tif")
    ]

    print(
        f"Finished {vf}: created {created_count}, skipped {skipped_count}, "
        f"errors {error_count}, total available {len(set(rasters))}"
    )

print("Result raster creation complete for all requested output fields!")
print(f"Run summary log: {run_summary_log}")
