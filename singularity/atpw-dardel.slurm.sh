#! /bin/bash -l

#SBATCH -A naiss2024-22-1518
#SBATCH -J atpw-dardel
#SBATCH -o atpw-dardel-%j.out
#SBATCH -p shared
#SBATCH -c 36
#SBATCH -t 01:00:00

# testing: use "-p shared -c 36 -t 01:00:00" and set "n_cpus=36" below
# run:     try "-p long   -N 1  -t 24:00:00" and set "n_cpus=256" below

# atpw-dardel.slurm.sh
# Last modified: ons jun 18, 2025  10:22
# Sign: JN
#
# Test by using
#     sbatch --test-only atpw-dardel.slurm.sh infolder outfolder
# Start by using
#     sbatch atpw-dardel.slurm.sh infolder outfolder
# Stop by using
#     scancel 1234
#     scancel -i -u $USER
#     scancel --state=pending -u $USER
# Monitor by using
#     squeue -u $USER
#
# More reading: https://www.pdc.kth.se/support/documents/run_jobs/job_scheduling.html
#
# Note: On dardel, a singularity image needs to be run as a "sandbox"!
# To convert a .sif to sandbox, use (on an existing atpw.sif on dardel):
#     ml PDC/24.11 singularity
#     singularity build --sandbox atpw atpw.sif
# And then run:
#     singularity run atpw -h
# More reading: https://www.pdc.kth.se/support/documents/software/singularity.html
#
# Note 2: On dardel, one may consider using different resources. Two alternatives
# may be to use '-p shared' in combination with '-c N' (and then use N as argument to
# atpw option: '-n N'). This will ask for N number of "cores", distributed over nodes.
# The other option on dardel would be to use '-p long' and '--nodes=1'. Note that
# '--nodes' is the same as '-N'.
#
# Note 3: On a test data with 144 .fas files, 47-136 taxa, 140-2260 avg length, the
# run took 9 minutes to complete.

# Testing
#   $ ml PDC/24.11 singularity
#   $ ATPW=/cfs/klemming/projects/supr/nrmdnalab_storage/src/Align-and-trees-parallel-workflow/singularity/atpw
#   $ export ATPW
#   $ singularity run $ATPW -h
#   $ cd /cfs/klemming/projects/supr/nrmdnalab_storage/tmp/atpw-testing
#   $ sbatch atpw-dardel.slurm.sh 9_fasta_files 9_fasta_files_out

ml PDC/24.11
ml singularity

ATPW="${ATPW:-/cfs/klemming/projects/supr/nrmdnalab_storage/src/Align-and-trees-parallel-workflow/singularity/atpw}"
               # ^ Edit path above to atpw sandbox
data_type='nt' # < Edit here if not nt input
n_cpus=36      # < 256: One node on dardel

start=$(date +%s)

if (( $# < 2 )) ; then
  echo "Usage: sbatch atpw-dardel.slurm.sh infolder outfolder"
  exit
fi

in_folder=$1
out_folder=$2

basename_in_folder=$(basename "${in_folder}")
tmp_in_folder="${basename_in_folder}"
cp -r "${in_folder}" "$SNIC_TMP"

if [ -d "${out_folder}" ]; then
  echo "Directory ${out_folder} exists. Exiting."
  exit
fi

if [ -d "${SNIC_TMP}${out_folder}" ]; then
  rm -rf "${SNIC_TMP}${out_folder}"
fi

basename_out_folder=$(basename "${out_folder}")
tmp_out_folder="${basename_out_folder}"

cp -r "${in_folder}" "$SNIC_TMP"

cd "$SNIC_TMP" || exit

singularity run "${ATPW}" -d "${data_type}" -n "${n_cpus}" "${tmp_in_folder}" "${tmp_out_folder}" && cp -r "${tmp_out_folder}" "$SLURM_SUBMIT_DIR/${basename_out_folder}"

end=$(date +%s)
runtime=$((end-start))
eval "echo Run took $(date -ud "@$runtime" +'$((%s/3600/24)) days %H hours %M minutes %S seconds')"

