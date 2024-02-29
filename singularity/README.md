# Singularity container for ATPW

- Last modified: tor feb 29, 2024  11:55
- Sign: JN

## Requirements

Singularity. See official install instructions:
<https://docs.sylabs.io/guides/3.0/user-guide/installation.html>

## Build a singularity container from the [definition file](atpw.def)

Run from git repo root directory (will copy scripts correctly)

    $ sudo singularity build singularity/atpw.sif singularity/atpw.def

## Run

    $ singularity/atpw.sif -h
    $ singularity/atpw.sif -d nt data out

