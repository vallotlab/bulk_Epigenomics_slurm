#!/bin/bash
set -euo pipefail

sample_sheet=$1
output_dir=$2
params=${3:-}

# Constants paths

script_dir=/mnt/beegfs/home/gjouault/Gitlab/bulk_Epigenomics_slurm
image=/mnt/beegfs/home/gjouault/Singularity/bulk_Epigenomics/bulkEpigenomics.sif
bind_directory=/data/
cores=12
mem=60G
walltime=164:00:00

stagein_root=/mnt/beegfs/home/gjouault/stagein
persistent_root=/mnt/beegfs/home/gjouault/persistent

cd $script_dir

# Load utility commands for sync_stage.sh if needed
module load utility 2>/dev/null || true

# Extract the first column value from the sample sheet
# Assumes:
# - first line is a header
# - first column contains the sample-set number
number_samplesheet=$(awk -F ',' 'NR==2 {print $1}' "$sample_sheet")

if [ -z "$number_samplesheet" ]; then
    echo "Error: could not extract number_samplesheet from first column of $sample_sheet"
    exit 1
fi

echo "Detected number_samplesheet: $number_samplesheet"

# Stage in KDI data to BeeGFS
# Source:
#   /data/kdi_prod/dataset_all/<number_samplesheet>/export/user/
# Destination:
#   /mnt/beegfs/home/gjouault/stagein/<number_samplesheet>/
mkdir -p "$stagein_root/$number_samplesheet"

module load utility

echo "Staging input data from KDI..."
sync_stage.sh \
    -l \
    -a \
    -s kdi_prod \
    -p "dataset_all/${number_samplesheet}/export/user" \
    -w "$stagein_root/$number_samplesheet"

# Copy the pipeline to the output directory & delete old logs if present
mkdir -p "$output_dir"
mkdir -p "$output_dir/logs"

cp -rf Scripts "$output_dir/"
cp -rf annotations "$output_dir/"
cp -f run_bulk_Epigenomics.sh "$output_dir/"
cp -f Snakefile_bulk_Epigenomics.py "$output_dir/"
cp -f species_design_configs.tsv "$output_dir/"
cp -f CONFIG_TEMPLATE.yaml "$output_dir/"
cp -f "$sample_sheet" "$output_dir/"
rm -f "$output_dir"/logs/*.log

# Create sample configuration file
# python3 Scripts/sample2json.py -i $sample_sheet -o $output_dir/ -c $output_dir/species_design_configs.tsv 
# Example: run sample2json inside container
singularity exec \
  --bind ${stagein_root}:/stagein \
  --bind /mnt/beegfs/home/gjouault:/mnt/beegfs/home/gjouault \
  "$image" \
  python3 "$script_dir/Scripts/sample2json.py" \
    -i "$sample_sheet" \
    -o "$output_dir/" \
    -c "$output_dir/species_design_configs.tsv"

# Submit the pipeline with Slurm
job_name=$(basename "$output_dir")

# Launch the pipeline using Singularity Image

sbatch \
  --job-name="$job_name" \
  --cpus-per-task="$cores" \
  --mem="$mem" \
  --time="$walltime" \
  --output="$output_dir/logs/slurm-%j.out" \
  --error="$output_dir/logs/slurm-%j.err" \
  --wrap="singularity exec \
    --bind /mnt/beegfs/home/gjouault:/mnt/beegfs/home/gjouault \
    --bind ${stagein_root}:/stagein \
    --bind ${output_dir}:/mnt \
    $image \
    /bin/bash -c '/mnt/run_bulk_Epigenomics.sh ${cores} ${params}'"


#echo "singularity  exec --bind ${bind_directory}:${bind_directory} --bind ${output_dir}:/mnt/ $image /bin/bash -c \"/mnt/run_bulk_Epigenomics.sh ${cores} ${params}\" " | qsub -l nodes=1:ppn=$cores,mem=60gb,walltime=164:00:00 -N $(basename ${output_dir})

