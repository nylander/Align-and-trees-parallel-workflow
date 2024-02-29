#!/usr/bin/bash -l
#SBATCH -t 0:30:00
#SBATCH -A naiss2023-22-913
#SBATCH -p core
#SBATCH -n 10

cd /proj/stylops_storage/nobackup/tmp
singularity run /proj/stylops/nobackup/share/bin/atpw.sif -d nt -i 100 data out

