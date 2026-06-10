#!/bin/bash

#--------------------------------------------------------------------------------------
# Name:         singleSubmit.sh
# Purpose:      Submit one BFAST job for a selected input CSV while skipping the job if
#               the expected output files already exist.
# Usage:        bash singleSubmit.sh <input_csv_name>
# Example:      bash singleSubmit.sh Centroids_80_fill.csv
# Notes:        The input file name should be relative to the inputDir setting below.
# Notes:        Update the user settings below as needed before running.
#				The input file name should be relative to the inputDir setting below.
#--------------------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# User settings
# -----------------------------------------------------------------------------

numCores=12          # Number of cores to run each job on
memoryPerCpu="700MB" # Memory requested per CPU; 12 cores x 700 MB = 8400 MB total
outputDir="Output2"  # Folder where BFAST output files are written
inputDir="Extract"   # Folder containing input CSV files

getTileNum () {
	basename "$1" | cut -d'_' -f 2
}

outputExists () {
	tileNum=$(getTileNum "$1")

	if [ -s "${outputDir}/${tileNum}_trend_breaks_time.txt" ] && \
	   [ -s "${outputDir}/${tileNum}_trend_breaks_magnitude.txt" ] && \
	   [ -s "${outputDir}/${tileNum}_trend_nbbreaks.txt" ] && \
	   [ -s "${outputDir}/${tileNum}_trend_bfast.txt" ] && \
	   [ -s "${outputDir}/${tileNum}_season_nbbreaks.txt" ] && \
	   [ -s "${outputDir}/${tileNum}_season_breaks_time.txt" ] && \
	   [ -s "${outputDir}/${tileNum}_season_bfast.txt" ] && \
	   [ -s "${outputDir}/${tileNum}_trend_breaks_confint.txt" ] && \
	   [ -s "${outputDir}/${tileNum}_season_breaks_confint.txt" ] && \
	   [ -s "${outputDir}/${tileNum}_residuals_bfast.txt" ] && \
	   [ -s "${outputDir}/${tileNum}_nobs.txt" ]; then
		return 0
	else
		return 1
	fi
}

file="${inputDir}/$1"
echo "$file" #Print the file name

if outputExists "$file"; then
	echo "Skipping $file because output files already exist in ${outputDir}."
	exit 0
fi

fileSize=$(stat -c%s "$file") #Get the size of the .csv file in bytes
hrsToRequest=$(( ($fileSize / 26214400) + 48 )) #This will figure out how many hours a job should run for
#The math from above written out: hours to request = ((tile file size in bytes / 25 megabytes in bytes) + 10) where the 24 hours added on gives enough overhead for all node classes

sbatch --job-name="bfast$(getTileNum "$file")" --time=$hrsToRequest:00:00 --constraint="wizards|heroes|moles|dwarves" --ntasks-per-node=$numCores --mem-per-cpu=$memoryPerCpu bfastParallel.sh $numCores "$file"

#The constraint runs jobs on the five node classes listed because they have the most nodes per class and best run time
