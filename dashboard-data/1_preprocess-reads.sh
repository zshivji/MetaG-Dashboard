#!/bin/bash
#===============================================================================
# SLURM Array Job: Read Preprocessing with BBTools
#===============================================================================
# Usage:  sbatch 1_preprocess-reads.sh
# Config: config.tsv (tab-separated, with header row)
#
# Requirements:
#   - bbmap installation: /resnick/groups/enviromics/tools/bbmap
#   - fastqc installation: /resnick/groups/enviromics/tools/FastQC
#   - for ease of use, add these locations to you PATH
#
# Description:
#   Concat reads from L1 and L2 maintaing forward/reverse files
#   Adapter identification (bbmerge) → adapter trimming (bbduk) →
#   quality trimming (bbduk) → FastQC on cleaned reads.
#
# Inputs:
#   - Paired-end FASTQ files (R1/R2) from Lane 1 and 2, paths specified in config
#
# Outputs:
#   - concat_reads/<sample>/<sample>_R1.fastq.gz 
#   - concat_reads/<sample>/<sample>_R2.fastq.gz
#   - fastq_processed/<sample>/<sample>_clean_R1.fastq.gz
#   - fastq_processed/<sample>/<sample>_clean_R2.fastq.gz
#   - fastq_processed/<sample>/fastqc/
#===============================================================================

#--- SLURM directives ---------------------------------------------------------
#SBATCH --job-name=bbduk
#SBATCH --time=04:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16GB
#SBATCH --array=1-20
#SBATCH --output=logs/%x-%A_%a.log

#--- Safety flags -------------------------------------------------------------
set -euo pipefail

#--- Configuration ------------------------------------------------------------
CONFIG="config.tsv"
THREADS=${SLURM_CPUS_PER_TASK:-8}

#--- Functions ----------------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

check_file() {
    local filepath="$1"
    local label="${2:-File}"
    if [[ ! -f "$filepath" ]]; then
        log "ERROR: ${label} not found: ${filepath}"
        exit 1
    fi
}

parse_config() {
    local config_file="$1"
    local task_id="$2"

    check_file "$config_file" "Config file"

    local row
    row=$(awk -F'\t' -v id="$task_id" 'NR>1 && $1==id' "$config_file")

    if [[ -z "$row" ]]; then
        log "ERROR: No config entry for SLURM_ARRAY_TASK_ID=${task_id}"
        exit 1
    fi

    SAMPLE=$(echo "$row"  | cut -f2)
    READS_R1=$(echo "$row" | cut -f3)
    READS_R2=$(echo "$row" | cut -f4)

    log "Parsed config: SAMPLE=${SAMPLE}"
}

#--- Main workflow ------------------------------------------------------------

main() {
    log "========== Job started =========="
    log "Job ID: ${SLURM_JOB_ID}, Array Task: ${SLURM_ARRAY_TASK_ID}"
    log "Node: $(hostname), CPUs: ${THREADS}"

    # Create output directories
    local outdir="fastq_processed"

    mkdir -p logs concat_reads
    mkdir -p "$outdir"
    mkdir -p "$outdir/fastqc"

    # Parse sample info from config
    parse_config "$CONFIG" "$SLURM_ARRAY_TASK_ID"

    # ---- Step 0: Concat reads from L1 and L2 ----
    log "Step 0: Concatenating reads for ${SAMPLE}"
    # Each sample is present in two raw-read directories, one per lane:
    #   raw_reads/Fall-2026__<sample>__L1_L1_ds/
    #   raw_reads/Fall-2026__<sample>__L2_L2_ds/
    # Concatenate R1 with R1 and R2 with R2, preserving paired-end reads.
    local lane1_dir="raw_reads/Fall-2026__${SAMPLE}__L1_L1_ds"
    local lane2_dir="raw_reads/Fall-2026__${SAMPLE}__L2_L2_ds"
    local concat_dir="concat_reads/${SAMPLE}"
    local lane1_r1 lane2_r1 lane1_r2 lane2_r2

    lane1_r1=$(find "$lane1_dir" -maxdepth 1 -type f -name '*_R1_001.fastq.gz' -print -quit)
    lane2_r1=$(find "$lane2_dir" -maxdepth 1 -type f -name '*_R1_001.fastq.gz' -print -quit)
    lane1_r2=$(find "$lane1_dir" -maxdepth 1 -type f -name '*_R2_001.fastq.gz' -print -quit)
    lane2_r2=$(find "$lane2_dir" -maxdepth 1 -type f -name '*_R2_001.fastq.gz' -print -quit)

    mkdir -p "$concat_dir"
    READS_R1="$concat_dir/${SAMPLE}_R1.fastq.gz"
    READS_R2="$concat_dir/${SAMPLE}_R2.fastq.gz"

    log "Concatenating L1/L2 reads for ${SAMPLE}"
    cat "$lane1_r1" "$lane2_r1" > "$READS_R1"
    cat "$lane1_r2" "$lane2_r2" > "$READS_R2"
    log "Created: $READS_R1"
    log "Created: $READS_R2"

    # ---- Step 1: Identify adapter sequences ----
    log "Step 1: Identifying adapters with bbmerge"
    bbmerge.sh \
        in1="$READS_R1" \
        in2="$READS_R2" \
        outa="$outdir/${SAMPLE}_adapters.fa"

    # ---- Step 2: Adapter trimming ----
    log "Step 2: Trimming adapters with bbduk"
    bbduk.sh \
        in="$READS_R1" \
        in2="$READS_R2" \
        out="$outdir/${SAMPLE}_tmp_R1.fastq.gz" \
        out2="$outdir/${SAMPLE}_tmp_R2.fastq.gz" \
        ref="$outdir/${SAMPLE}_adapters.fa" \
        threads="$THREADS" \
        ktrim=r k=23 mink=11 hdist=1 minlen=50 tpe tbo

    # ---- Step 3: Quality trimming ----
    log "Step 3: Quality trimming with bbduk"
    bbduk.sh \
        in="$outdir/${SAMPLE}_tmp_R1.fastq.gz" \
        in2="$outdir/${SAMPLE}_tmp_R2.fastq.gz" \
        out="$outdir/${SAMPLE}_clean_R1.fastq.gz" \
        out2="$outdir/${SAMPLE}_clean_R2.fastq.gz" \
        threads="$THREADS" \
        trimq=20 qtrim=r minlen=50

    # ---- Clean up intermediates ----
    log "Removing intermediate files"
    rm -f "$outdir/${SAMPLE}_tmp_R1.fastq.gz" "$outdir/${SAMPLE}_tmp_R2.fastq.gz"

    # ---- Step 4: FastQC ----
    log "Step 4: Running FastQC"
    fastqc \
        --outdir "$outdir/fastqc" \
        -t "$THREADS" \
        -f fastq \
        "$outdir/${SAMPLE}_clean_R1.fastq.gz" \
        "$outdir/${SAMPLE}_clean_R2.fastq.gz"

    log "========== Job finished =========="
}

main
