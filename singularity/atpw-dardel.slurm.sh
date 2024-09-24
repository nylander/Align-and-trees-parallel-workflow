#! /bin/bash -l

#SBATCH -A naiss2023-22-1239
#SBATCH -J atpw-dardel
#SBATCH -o atpw-dardel.out
#SBATCH -p long
#SBATCH -N 1
#SBATCH -t 03:00:00

# atpw-dardel.slurm.sh
# Last modified: tis sep 24, 2024  11:15
# Sign: JN
#
# Test by using
#     sbatch --test-only atpw-dardel.slurm.sh
# Start by using
#     sbatch atpw-dardel.slurm.sh
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
# run below took 9 minutes to complete.

ml PDC
ml singularity

start=$(date +%s)

cd /cfs/klemming/projects/supr/nrmdnalab_storage/tmp/atpw-testing

singularity run /cfs/klemming/projects/supr/nrmdnalab_storage/src/Align-and-trees-parallel-workflow/singularity/atpw -d nt -n 256 fasta_files fasta_files_out

end=$(date +%s)
runtime=$((end-start))
eval "echo Run took $(date -ud "@$runtime" +'$((%s/3600/24)) days %H hours %M minutes %S seconds')"

