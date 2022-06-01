# Align-and-trees-parallel-workflow

- Last modified: ons jun 01, 2022  12:59
- Sign: Johan.Nylander\@nrm.se

## Description

Script for running a "standard" phylogenetic workflow on fasta-formatted input.
In particular, parallel execution is done whenever possible.

On unfiltered fasta files,

1. Create multiple sequence alignments with mafft
2. Filter alignments using BMGE
3. Infer phylogenetic trees for each locus with fixed model using pargenes and raxml-ng
4. Filter trees using treeshrink
5. Do multiple sequence alignments on tree-filtered data using mafft
6. Infer phylogenetic trees for each locus with model selection using pargenes and raxml-ng
7. Estimate species tree from individual trees using ASTRAL

## Usage

    align-and-trees-parallel-workflow.sh [options] /path/to/folder/with/fas/files /path/to/output/folder
    align-and-trees-parallel-workflow.sh -h

## Input data

Unaligned aa or nt sequences in fasta formatted files, one per locus, placed in
a folder (which is the first argument to the script). The number of sequences
in the files does not need to be the same, but sequence labels should match if
the data comes from the same sample.  File names should end in `.fas`. Example:
`EOG7CKDX2.fas`.  The part `EOG7CKDX2` will be used as locus name in down
stream analyses. See [example data](data).

## Output

- Filtered alignments in `outputfolder/1_align/1.4_mafft_check_bmge_treeshrink/`
- Gene trees in `outputfolder/2_trees/2.2_mafft_check_bmge_treeshrink_pargenes/mlsearch_run/results`
- Species tree in `outputfolder/2_trees/2.2_mafft_check_bmge_treeshrink_pargenes/astral_run/`

## Installation

See the [`INSTALL`](INSTALL) file.

### Important caveats

1. Current version with command line options is experimental.
2. The path to some helper software **need to be hard coded (full path) in the script**.
3. The optimal total number of cores in combination with the number of parallel processes for GNU parallel,
and in combination with number of cores used for child processes are not yet optimized, nor checked for
inconsistencies. **Please adjust in the script as needed** (check your max N cores on your hardware).
4. Spell check of arguments are not yet implemented.

