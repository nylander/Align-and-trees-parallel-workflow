#! /bin/bash -l

#SBATCH -A naiss2023-22-1239
#SBATCH -J atpw-dardel
#SBATCH -o atpw-dardel.out
#SBATCH -p shared
#SBATCH -c 50
#SBATCH -t 01:30:00

# atpw-dardel.slurm.sh
# Last modified: fre sep 20, 2024  05:47
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
# Note: a singularity image needs to be run as a "sandbox"!
# To convert a .sif to sandbox, use (on an existing atpw.sif on dardel):
#     singularity build --sandbox atpw atpw.sif
# And then run:
#     singularity run atpw -h
#
# More reading: https://www.pdc.kth.se/support/documents/software/singularity.html

ml PDC
ml singularity

start=$(date +%s)

cd /cfs/klemming/projects/supr/nrmdnalab_storage/tmp/atpw-testing

singularity run /cfs/klemming/projects/supr/nrmdnalab_storage/src/Align-and-trees-parallel-workflow/singularity/atpw -d nt -n 50 fasta_files fasta_files_out

end=$(date +%s)
runtime=$((end-start))
eval "echo Run took $(date -ud "@$runtime" +'$((%s/3600/24)) days %H hours %M minutes %S seconds')"

