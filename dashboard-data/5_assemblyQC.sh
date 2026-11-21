#!/bin/bash
#===============================================================================
# SLURM Array Job Template
#===============================================================================
# Usage:  sbatch 4_assemblyQC.sh
# Config: config.tsv (tab-separated, with header row)
#
# Description:
#   - Runs metaSPAdes assembler on short reads
#   - Runs MEGAHIT assembler on short reads
#   - Assembly QC with QUAST
#===============================================================================

#--- SLURM directives ---------------------------------------------------------
#SBATCH --job-name=quast
#SBATCH --time=05:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=100GB
#SBATCH --array=1-20
#SBATCH --output=logs/%x_%A_%a.log
##SBATCH --dependency=afterok:7080176

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
    parse_config "$CONFIG" "$SLURM_ARRAY_TASK_ID"

    # Validate inputs
    check_file "$READS_R1" "Forward reads"
    check_file "$READS_R2" "Reverse reads"

    # Make Output Directories
    mkdir -p quast_results

    # ---- Step 1: metaQUAST ----
    log "Step 1: QCing Assemblies with QUAST "
    activate_env "/resnick/groups/enviromics/gsolini/miniconda3/envs/quast"
    
    # run metagenome assembly with spades
    metaquast.py \
        assembly/megahit/${SAMPLE}/final.contigs.fa \
        assembly/spades/${SAMPLE}/contigs.fasta \
        assembly/spades-noerror-correction/${SAMPLE}/contigs.fasta \
        -o quast_results/${SAMPLE} \
        -t $THREADS \
        --labels "MEGAHIT,metaSPAdes_EC,metaSPAdes" --max-ref-number 0


    # ---- Step 2: spades Bowtie Alignment  ----
    log "Step 2: Running Shotgun Alignment to both metaSPAdes assembly"

    bowtie2-build --threads $THREADS assembly/spades-noerror-correction/${SAMPLE}/scaffolds.fasta assembly/spades-noerror-correction/${SAMPLE}/scaffolds

    rate=$(bowtie2 -x assembly/spades-noerror-correction/${SAMPLE}/scaffolds \
      -1 fastq_processed/${SAMPLE}_clean_R1.fastq.gz \
      -2 fastq_processed/${SAMPLE}_clean_R2.fastq.gz \
      --threads ${THREADS} --no-unal -p 12 2>&1 >/dev/null | grep "overall alignment rate" | awk '{print $1}')
    
     echo -e "${SAMPLE}\tmetaspades_assemblyonly\t${rate}" >> alignment_rates.tsv


    # ---- Step 3: spades + EC Bowtie Alignment  ----
    log "Step 3: Running Shotgun Alignment to both metaSPAdes + EC assembly"

    bowtie2-build --threads $THREADS assembly/spades/${SAMPLE}/scaffolds.fasta assembly/spades/${SAMPLE}/scaffolds

    rate=$(bowtie2 -x assembly/spades/${SAMPLE}/scaffolds \
      -1 fastq_processed/${SAMPLE}_clean_R1.fastq.gz \
      -2 fastq_processed/${SAMPLE}_clean_R2.fastq.gz \
      --threads ${THREADS} --no-unal -p 12 2>&1 >/dev/null | grep "overall alignment rate" | awk '{print $1}')

     echo -e "${SAMPLE}\tmetaspades_EC\t${rate}" >> alignment_rates.tsv


    # ---- Step 4: MEGAHIT Bowtie Alignment  ----
    log "Step 4: Running Shotgun Alignment to MEGAHIT assembly"

    bowtie2-build --threads ${THREADS} assembly/megahit/${SAMPLE}/final.contigs.fa assembly/megahit/${SAMPLE}/final.contigs

    rate=$(bowtie2 -x assembly/megahit/${SAMPLE}/final.contigs \
      -1 fastq_processed/${SAMPLE}_clean_R1.fastq.gz \
      -2 fastq_processed/${SAMPLE}_clean_R2.fastq.gz \
      --threads ${THREADS} --no-unal -p 12 2>&1 >/dev/null | grep "overall alignment rate" | awk '{print $1}')
    
    echo -e "${SAMPLE}\tmegahit\t${rate}" >> alignment_rates.tsv

    log "========== Job finished =========="
}

# Run it
main
