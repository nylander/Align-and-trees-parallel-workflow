# Align-and-trees-parallel-workflow

- Last modified: fre jun 03, 2022  01:45
- Sign: Johan.Nylander\@nrm.se

## Description

Script for running a "standard" phylogenetic workflow on fasta-formatted input.
In particular, parallel execution is done whenever possible.

On unfiltered fasta files,

1. Create multiple sequence alignments with [mafft](https://mafft.cbrc.jp/alignment/software/)
2. Filter alignments using [BMGE](https://bmcecolevol.biomedcentral.com/articles/10.1186/1471-2148-10-210)
3. Infer phylogenetic trees for each locus with fixed model using [pargenes](https://github.com/BenoitMorel/ParGenes) and [raxml-ng](https://github.com/amkozlov/raxml-ng)
4. Filter trees using [TreeShrink](https://github.com/uym2/TreeShrink)
5. Do multiple sequence alignments on treeshrink-filtered data using mafft
6. Infer phylogenetic trees for each locus with [model selection](https://github.com/ddarriba/modeltest) using pargenes and raxml-ng
7. Estimate species tree from individual trees using [ASTRAL](https://github.com/smirarab/ASTRAL)

## Usage

    $ align-and-trees-parallel-workflow.sh -d nt|aa [options] /path/to/folder/with/fas/files /path/to/output/folder
    $ align-and-trees-parallel-workflow.sh -h

## Input data

Unaligned aa or nt sequences in fasta formatted files, one per locus, placed in
a folder (which is the first argument to the script). The number of sequences
in the files does not need to be the same, but sequence labels should match if
the data comes from the same sample.  File names should end in `.fas`. Example:
`EOG7CKDX2.fas`.  The part `EOG7CKDX2` will be used as locus name in down
stream analyses. See [example data](data).

## Output

- Alignments in `outputfolder/1_align/`
- Gene trees in `outputfolder/2_trees/2.2_mafft_check_bmge_treeshrink_pargenes/mlsearch_run/results`
- Species tree in `outputfolder/2_trees/2.2_mafft_check_bmge_treeshrink_pargenes/astral_run/`
- Log file in `outputfolder/align-and-trees-parallel-workflow.log`
- Summary file in `outputfolder/README.md`

## Installation

See the [`INSTALL`](INSTALL) file.

### Important caveats

* The path to some helper software **need to be hard coded (full path) in the script**.
* The optimal total number of cores in combination with the number of parallel processes for GNU parallel,
and in combination with number of cores used for child processes are not yet optimized, nor checked for
inconsistencies.

