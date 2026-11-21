#!/bin/bash
#===============================================================================
# SLURM Array Job Template
#===============================================================================
# Usage:  sbatch 2_decontaminate.sh
# Config: config.tsv (tab-separated, with header row)
#
# Requirements:
#   - bowtie2 installation
#   - for ease of use, add these locations to you PATH
#
# Description:
#   Remove reads that map to the human genome.
#
# Inputs:
#   - fastq_processed/<sample>_clean_R1.fastq.gz
#   - fastq_processed/<sample>_clean_R2.fastq.gz
#
# Outputs:
#   - fastq_processed/<sample>_decon_R1.fastq.gz
#   - fastq_processed/<sample>_decon_R1.fastq.gz
#===============================================================================

#--- SLURM directives ---------------------------------------------------------
#SBATCH --job-name=decon
#SBATCH --time=08:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=12
#SBATCH --mem=64GB
#SBATCH --array=1-20
#SBATCH --output=logs/%x-%A_%a.log
##SBATCH --dependency=afterok:6995820

#--- Safety flags -------------------------------------------------------------
set -euo pipefail

#--- Configuration ------------------------------------------------------------
CONFIG="config.tsv"
THREADS=${SLURM_CPUS_PER_TASK:-12}

#--- Functions ----------------------------------------------------------------

log() {
    # Timestamped logging to stderr (so stdout stays clean for piping)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

check_file() {
    # Exit with a clear message if a required file is missing
    local filepath="$1"
    local label="${2:-File}"
    if [[ ! -f "$filepath" ]]; then
        log "ERROR: ${label} not found: ${filepath}"
        exit 1
    fi
}

check_dir() {
    # Exit with a clear message if a required directory is missing
    local dirpath="$1"
    local label="${2:-Directory}"
    if [[ ! -d "$dirpath" ]]; then
        log "ERROR: ${label} not found: ${dirpath}"
        exit 1
    fi
}

parse_config() {
    # Parse a header-aware TSV config file.
    # Reads column values by position (skipping the header row).
    # Usage: assigns variables based on the SLURM_ARRAY_TASK_ID row.
    local config_file="$1"
    local task_id="$2"

    check_file "$config_file" "Config file"

    # Read the row matching this array task ID (column 1 = task ID)
    local row
    row=$(awk -F'\t' -v id="$task_id" 'NR>1 && $1==id' "$config_file")

    if [[ -z "$row" ]]; then
        log "ERROR: No config entry for SLURM_ARRAY_TASK_ID=${task_id}"
        exit 1
    fi

    # ---- Extract columns (edit these to match your config.tsv) ----
    SAMPLE=$(echo "$row"  | cut -f2)
    READS_R1="fastq_processed/${SAMPLE}_clean_R1.fastq.gz"
    READS_R2="fastq_processed/${SAMPLE}_clean_R2.fastq.gz"
    # SOME_PARAM=$(echo "$row" | cut -f5)

    log "Parsed config: SAMPLE=${SAMPLE}"
}

activate_env() {
    # Activate a conda environment by name
    local env_name="$1"
    eval "$(conda shell.bash hook)"
    conda activate "$env_name"
    log "Activated conda env: ${env_name}"
}

#--- Main workflow ------------------------------------------------------------

main() {
    log "========== Job started =========="
    log "Job ID: ${SLURM_JOB_ID}, Array Task: ${SLURM_ARRAY_TASK_ID}"
    log "Node: $(hostname), CPUs: ${THREADS}"

    # Create log directory if needed
    mkdir -p logs

    # Parse sample info from config
    parse_config "$CONFIG" "$SLURM_ARRAY_TASK_ID"

    # Validate inputs
    check_file "$READS_R1" "Forward reads"
    check_file "$READS_R2" "Reverse reads"

    # ---- Step 1: <Description> ----
    log "Step 1: Removing Potential Host Contamination"
    
    # map to human genome, keep only unmapped pairs
    bowtie2 -x /resnick/groups/enviromics/databases/hg38/hg38 \
        -1 $READS_R1 \
        -2 $READS_R2 \
        --very-sensitive \
        --threads $THREADS \
        --un-conc-gz fastq_processed/${SAMPLE}_decon_R%.fastq.gz \
        -S /dev/null

    log "========== Job finished =========="
}

# Run it
main
