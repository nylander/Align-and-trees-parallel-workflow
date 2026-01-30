#! /bin/bash -l

#SBATCH -A uppmax2025-2-162
#SBATCH -J atpw-pelle
#SBATCH -o atpw-pelle-%j.out
#SBATCH -c 36
#SBATCH -t 01:00:00

# testing: use "-c 36 -t 01:00:00" above and set "n_cpus=36" below
# run:     try "-N 1  -t 24:00:00" above and set "n_cpus=96" below
# Note: one node on pelle has 48 cores (96 threads)

# atpw-pelle.slurm.sh
# Last modified: 2026-01-30 15:17:34
# Sign: JN
#
# Test by using
#     sbatch --test-only atpw-pelle.slurm.sh infolder outfolder
# Start by using
#     sbatch atpw-pelle.slurm.sh infolder outfolder
# Stop by using
#     scancel 1234
#     scancel -i -u $USER
#     scancel --state=pending -u $USER
# Monitor by using
#     squeue -u $USER
#
# More reading: https://docs.uppmax.uu.se/cluster_guides/slurm_on_pelle
#
# Testing (JN)
#   $ cd $HOME/run/atpw-testing
#   $ sbatch atpw-pelle.slurm.sh 7_fasta_files 7_fasta_files_out

# ------------------------------------------------------------
ATPW="${ATPW:-$HOME/bin/atpw.sif}"
                 # ^ Edit path above to atpw
data_type='nt'   # < Edit here if not nt input
n_cpus="${SLURM_CPUS_PER_TASK}"
other_options=' -i 1000 ' # Other options to atpw here
# ------------------------------------------------------------

start=$(date +%s)

if [ $# -lt 2 ] ; then
  echo "Usage: sbatch atpw-pelle.slurm.sh infolder outfolder"
  exit
fi

in_folder=$1
out_folder=$2

if [ -d "${out_folder}" ]; then
  echo "Directory ${out_folder} exists. Exiting."
  exit
fi

#singularity run "${ATPW}" -d "${data_type}" -n "${n_cpus}" "${other_options}" "${in_folder}" "${out_folder}"

# NOTE: hard coded bootstrap!
singularity run -B "${SNIC_TMP}" "${ATPW}" -d "${data_type}" -n "${n_cpus}" -i 1000 "${in_folder}" "${out_folder}"

end=$(date +%s)
runtime=$((end-start))
eval "echo Run took $(date -ud "@$runtime" +'$((%s/3600/24)) days %H hours %M minutes %S seconds')"

