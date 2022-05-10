# Align-and-trees-parallel-workflow

- Last modified: tis maj 10, 2022  06:28
- Sign: Johan.Nylander\@nrm.se

## Description

Script for running a "standard" phylogenetic workflow on fasta-formatted input.
In particular, parallel execution is done whenever possible.

On unfiltered fasta files,

1. Create multiple sequence alignments with mafft
2. Filter alignments using BMGE
3. Infer phylogenetic trees for each locus with fixed model using pargenes and raxml-ng
4. Filter trees using treeshrink
5. Do multiple sequence alignments on tree-filtered data uisng mafft
6. Infer phylogenetic trees for each locus with model selection using pargenes and raxml-ng
7. Estimate species tree from individual trees using ASTRAL

## Usage

    align-and-trees-parallel-workflow.sh [options] /path/to/folder/with/fas/files /path/to/output/folder
    align-and-trees-parallel-workflow.sh -h

## Input data

Unaligned aa or nt sequences (need to specify manually in the script) in fasta
formatted files, one per locus, placed in a folder (which is the first argument
to the script). The number of sequences in the files does not need to be the
same, but sequence labels should match if the data comes from the same sample.
File names should end in `.fas`. Example: `EOG7CKDX2.fas`.  The part `EOG7CKDX2`
will be used as locus name in down stream analyses. See [example data](data).

## Output

- Filtered alignments in `outputfolder/treeshrink/realign-bmge/`
- Gene trees in `outpfolder/trees/pargenes-bmge-treeshrink/`
- Species tree in `outputfolder/trees/pargenes-bmge-treeshrink/astral_run/`

## Installation

See the [`INSTALL`](INSTALL) file.

### Important

Current version with command line options are experimental.

1. The path to the `BMGE.jar` can be supplied (full path) on command line using the `-b` option.
It is, however, recommended to edit the script instead.

2. The optimal total number of cores in combination with the number of parallel processes for GNU parallel,
and in combination with number of cores used for child processes are not yet optimized, nor checked for
inconsistencies. **Please adjust in the script as needed** (check your max N cores on your hardware).

3. Spell check of arguments are not yet implemented.
