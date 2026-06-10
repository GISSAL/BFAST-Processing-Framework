#!/bin/bash

#--------------------------------------------------------------------------------------
# Name:         superSubmit.sh
# Purpose:      Submit BFAST jobs for all Extract/*.csv files, or for an optional
#               numeric tile range, while skipping tiles whose output files already exist.
# Usage:        bash superSubmit.sh
#               bash superSubmit.sh <startTile> <endTile>
# Example:      bash superSubmit_.sh 80 120
# Notes:        Update the user settings below as needed before running.
#--------------------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# User settings
# -----------------------------------------------------------------------------

numCores=12          # Number of cores to run each job on
memoryPerCpu="700MB" # Memory requested per CPU; 12 cores x 700 MB = 8400 MB total
outputDir="Output2"  # Folder where BFAST output files are written
inputDir="Extract"   # Folder containing input CSV files

# Optional range arguments:
#   bash superSubmit.sh          # check all files
#   bash superSubmit.sh 80 120   # check only tiles 80 through 120
if [ "$#" -eq 0 ]; then
	useRange=0
elif [ "$#" -eq 2 ]; then
	useRange=1
	startTile=$1
	endTile=$2

	if ! [[ "$startTile" =~ ^[0-9]+$ ]] || ! [[ "$endTile" =~ ^[0-9]+$ ]]; then
		echo "ERROR: range values must be numeric."
		echo "Usage: bash superSubmit_check_outputs_range.sh [startTile endTile]"
		exit 1
	fi

	if [ "$startTile" -gt "$endTile" ]; then
		echo "ERROR: startTile must be less than or equal to endTile."
		exit 1
	fi
else
	echo "ERROR: provide either no range or both startTile and endTile."
	echo "Usage: bash superSubmit_check_outputs_range.sh [startTile endTile]"
	exit 1
fi

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

for file in "${inputDir}"/*.csv #For each file in the input folder with a .csv extension
do
	tileNum=$(getTileNum "$file")

	# If a range was provided, skip files outside the range.
	if [ "$useRange" -eq 1 ]; then
		if ! [[ "$tileNum" =~ ^[0-9]+$ ]]; then
			echo "Skipping $file because tile number could not be parsed."
			continue
		fi

		if [ "$tileNum" -lt "$startTile" ] || [ "$tileNum" -gt "$endTile" ]; then
			echo "Skipping $file because tile $tileNum is outside requested range $startTile-$endTile."
			continue
		fi
	fi

	echo "$file" #Print the file name

	if outputExists "$file"; then
		echo "Skipping $file because output files already exist in ${outputDir}."
		continue
	fi

	fileSize=$(stat -c%s "$file") #Get the size of the .csv file in bytes
	hrsToRequest=$(( ($fileSize / 26214400) + 24 )) #This will figure out how many hours a job should run for
	#The math from above written out: hours to request = ((tile file size in bytes / 25 megabytes in bytes) + 10) where the 24 hours added on gives enough overhead for all node classes

	sbatch --job-name="bfast${tileNum}" --time=$hrsToRequest:00:00 --constraint="wizards|heroes|moles|dwarves" --ntasks-per-node=$numCores --mem-per-cpu=$memoryPerCpu bfastParallel.sh $numCores "$file"

	#The constraint runs jobs on the five node classes listed because they have the most nodes per class and best run time
done