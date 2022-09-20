#!/bin/bash -l
#SBATCH -t 0:15:00
#SBATCH -A snic2022-5-27
#SBATCH -p core
#SBATCH -n 10

cd /home/nylander/src/Align-and-trees-parallel-workflow/
singularity run singularity/atpw.sif -d nt data out

