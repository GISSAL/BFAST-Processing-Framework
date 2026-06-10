#!/usr/bin/env python
# -*- coding: utf-8 -*-

#    File name: PythonScript_CreateTileShapefiles.py
#    Author: Shawn Hutchinson
#    Description:  Extracts points within fishnet polygons and exports them as a new shapefile
#    Date created: 04/29/2026
#    Python Version: 3.13.7

# Import required module(s)
import arcpy
import os

# Set environment(s)
arcpy.env.workspace = r"D:\Research\Projects\BFAST_2001_2025\BFAST_Analysis\BFAST_Analysis.gdb"
arcpy.env.overwriteOutput = True

# Inputs
points_fc = r"GrasslandAllYears_Majority_Centroids"
fishnet_fc = r"Fishnet50K"

# Output folder
out_folder = r"D:\Research\Projects\BFAST_2001_2025\BFAST\tiles"

# Field in Fishnet50K containing the tile number
tile_field = "Tile"  # <-- change this to the actual tile number field

# Create required layer files
points_lyr = "points_lyr"
fishnet_lyr = "fishnet_lyr"

# Perform geoprocessing
arcpy.MakeFeatureLayer_management(points_fc, points_lyr)
arcpy.MakeFeatureLayer_management(fishnet_fc, fishnet_lyr)

with arcpy.da.SearchCursor(fishnet_fc, ["OID@", tile_field, "SHAPE@"]) as cursor:
    for oid, tile_num, geom in cursor:
        out_name = f"Centroids_{tile_num}.shp"
        out_path = os.path.join(out_folder, out_name)

        if arcpy.Exists(out_path):
            print(f"Skipping tile {tile_num}: output already exists")
            continue

        arcpy.SelectLayerByLocation_management(
            in_layer=points_lyr,
            overlap_type="INTERSECT",
            select_features=geom,
            selection_type="NEW_SELECTION"
        )

        count = int(arcpy.GetCount_management(points_lyr)[0])

        if count > 0:
            arcpy.CopyFeatures_management(points_lyr, out_path)
            print(f"Exported {count} points to {out_path}")
        else:
            print(f"Skipping tile {tile_num}: no intersecting points")

        arcpy.SelectLayerByAttribute_management(points_lyr, "CLEAR_SELECTION")

# Count the number of  shapefiles in the output folder
shapefiles = [
    f for f in os.listdir(out_folder)
    if f.lower().startswith("centroids_") and f.lower().endswith(".shp")
]

unique_count = len(set(shapefiles))

# Print final messages
print("Tile creation completed!")
print(f"\nTotal unique Centroids shapefiles in output folder: {unique_count}")
