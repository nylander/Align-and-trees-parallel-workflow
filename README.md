# Align-and-trees-parallel-workflow

- Last modified: mån aug 01, 2022  11:45
- Sign: Johan.Nylander\@nrm.se

## Description

Script for running a "standard" phylogenetic workflow on fasta-formatted input.
In particular, parallel execution is done whenever possible.

The default steps on unfiltered and unaligned fasta files as input (see [Input
data](#input-data)) are,

1. Create multiple sequence alignments with [MAFFT](https://mafft.cbrc.jp/alignment/software/)
2. Filter alignments using [BMGE](https://bmcecolevol.biomedcentral.com/articles/10.1186/1471-2148-10-210)
3. Infer phylogenetic trees for each locus with fixed model using [ParGenes](https://github.com/BenoitMorel/ParGenes) and [RAxML-NG](https://github.com/amkozlov/raxml-ng)
4. Filter trees using [TreeShrink](https://github.com/uym2/TreeShrink)
5. Do multiple sequence alignments on treeshrink-filtered data using MAFFT
6. Infer phylogenetic trees for each locus with [model selection](https://github.com/ddarriba/modeltest) using ParGenes and RAxML-NG
7. Estimate species tree from individual trees using [ASTRAL](https://github.com/smirarab/ASTRAL)

Steps 1. and 2. are optional (see [Options](#options)).

## Usage

    $ align-and-trees-parallel-workflow.sh -d nt|aa [options] /path/to/folder/with/fas/files /path/to/output/folder
    $ align-and-trees-parallel-workflow.sh -h

## Options

    -d type   -- Specify data type: nt or aa (Mandatory)
    -t number -- Specify the number of threads
    -m crit   -- Model test criterion: BIC, AIC or AICc
    -A        -- Do not run initial alignment (assume aligned input)
    -B        -- Do not run BMGE
    -v        -- Print version
    -h        -- Print help message

## Input data

Unaligned aa or nt sequences in fasta formatted files, one per locus, placed in
a folder (which is the first argument to the script). The number of sequences
in the files does not need to be the same, but sequence labels should match if
the data comes from the same sample.  File names should end in `.fas`. Example:
`EOG7CKDX2.fas`.  The part `EOG7CKDX2` will be used as locus name in down
stream analyses. See [example data](data).

The sequences in the input files are assumed to be unaligned, and where the
first step in the workflow is to attempt to do multiple-sequence alignment.  If
the input files are already aligned, the workflow needs to be started with the
`-A` option.

## Output

- Alignments in `outputfolder/1_align/`
- Gene trees in `outputfolder/2_trees/2.2_mafft_check_bmge_treeshrink_pargenes/mlsearch_run/results`
- Species tree in `outputfolder/2_trees/2.2_mafft_check_bmge_treeshrink_pargenes/astral_run/`
- Log file in `outputfolder/ATPW.log`
- Summary file in `outputfolder/README.md`

## Installation

See the [`INSTALL`](INSTALL) file.

### Important caveats

* The path to some helper software **need to be hard coded (full path) in the script**.
* The optimal total number of cores in combination with the number of parallel processes for GNU parallel,
and in combination with number of cores used for child processes are not yet optimized, nor checked for
inconsistencies.

