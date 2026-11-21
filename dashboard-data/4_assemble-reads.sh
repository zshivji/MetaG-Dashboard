#!/bin/bash
#===============================================================================
# SLURM Array Job Template
#===============================================================================
# Usage:  sbatch 3_assemble-reads.sh
# Config: config.tsv (tab-separated, with header row)
#
# Requirements:
#   - megahit env: currently using /resnick/groups/enviromics/gsolini/miniconda3/envs/megahit
#   - spades env:  currentl using /resnick/groups/enviromics/gsolini/miniconda3/envs/spades
#
# Description:
#   - Runs metaSPAdes assembler on short reads
#   - Runs MEGAHIT assembler on short reads
#   - Assembly QC with QUAST
#===============================================================================

#--- SLURM directives ---------------------------------------------------------
#SBATCH --job-name=assemble
#SBATCH --time=15:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=100GB
#SBATCH --array=1
#SBATCH --output=logs/%x-%A_%a.log

#--- Safety flags -------------------------------------------------------------
set -euo pipefail

#--- Configuration ------------------------------------------------------------
CONFIG="config.tsv"
THREADS=${SLURM_CPUS_PER_TASK:-12}

MEM_BYTES=$(( ${SLURM_MEM_PER_NODE:-204800} * 1024 * 1024 ))
MEM_GB=$(( ${SLURM_MEM_PER_NODE:-204800} / 1024 ))

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
    READS_R1=$(echo "$row" | cut -f3)
    READS_R2=$(echo "$row" | cut -f4)
    # Add more columns as needed:
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
    parse_config "$CONFIG" "15"

    # Validate inputs
    check_file "$READS_R1" "Forward reads"
    check_file "$READS_R2" "Reverse reads"

    # Make Output Directories
    mkdir -p assembly/megahit
    mkdir -p assembly/spades

#    # ---- Step 1: MEGAHIT> ----
#    log "Step 1: Running Assembly with MEGAHIT"
#    activate_env "/resnick/groups/enviromics/gsolini/miniconda3/envs/megahit"    
#    # run megahit
#    megahit \
#        -1 fastq_processed/${SAMPLE}_decon_R1.fastq.gz \
#        -2 fastq_processed/${SAMPLE}_decon_R2.fastq.gz \
#        -o assembly/megahit/${SAMPLE} \
#        -m $MEM_BYTES \
#        -t $THREADS

    # ---- Step 2: metaSPAdes ----
    log "Step 2: Running Assembly with metaSPAdes"
    export JAVA_HOME="${JAVA_HOME:-}"
    activate_env "/resnick/groups/enviromics/gsolini/miniconda3/envs/spades"
    # run metaspades
#    metaspades.py \
#        -1 fastq_processed/${SAMPLE}_decon_R1.fastq.gz \
#        -2 fastq_processed/${SAMPLE}_decon_R2.fastq.gz \
#        -o assembly/spades/${SAMPLE} \
#        -k 21,33,55,77,99,127 \
#        -m $MEM_GB \
#        -t $THREADS
#        --only-assembler

   # continue if needed (if runtime exceeds limit)
   metaspades.py --continue -o assembly/spades/${SAMPLE}

    log "========== Job finished =========="
}

# Run it
main
