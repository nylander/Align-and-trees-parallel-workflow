# Align-and-trees-parallel-workflow

- Last modified: tis maj 10, 2022  03:28
- Sign: Johan.Nylander\@nrm.se

## Description

Script for running a "standard" phylogenetic workflow on fasta-formatted input.
In particular, parallel execution is done whenever possible.


On unfiltered fasta files,

1. Create multiple sequence alignments with mafft
2. Filter alignments using BMGE
3. Infer phylogenetic trees for each locus with fixed model using pargenes and raxml-ng
4. Filter trees using treeshrink
5. Do multiple sequence alignments on filtered tree-filtered data uisng mafft
6. Infer phylogenetic trees for each locus with model selection using pargenes and raxml-ng
7. Estimate species tree from individual trees using ASTRAL

## Usage

    ./align-and-trees-workflow.sh /path/to/folder/with/fas/files /path/to/output/folder

## Input data

Unaligned aa or nt sequences (need to specify manually in the script) in fasta
formatted files, one per locus, placed in a folder (which is the first argument
to the script). The number of sequences in the files does not need to be the
same, but sequence labels should match if the data comes from the same sample.
File names should en in `.fas`. Example: `EOG7CKDX2.fas`.  The part `EOG7CKDX2`
will be used as locus name in down stream analyses. See [example data](data).

## Output

text


## Installation

See the [`INSTALL`](INSTALL) file.

### Important

Currently, paths to some binaries needs to be manually adjusted inside the
[align-and-trees-workflow.sh](src/align-and-trees-workflow.sh) script, as well
as number of available cores!

