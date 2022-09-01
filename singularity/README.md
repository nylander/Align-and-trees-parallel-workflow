# Singularity container for ATPW

- Last modified: tor sep 01, 2022  11:16
- Sign: JN

## Requirements

Singularity. See official install instructions:
<https://docs.sylabs.io/guides/3.0/user-guide/installation.html>

## Build a singularity container from the [definition file](atpw.def)

    $ sudo singularity build atpw.sif atpw.def

## Run

    $ ./atpw.sif -h
    $ ./atpw.sif -d nt data out

