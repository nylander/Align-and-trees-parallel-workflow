# Align-and-trees-workflow

- Last modified: tis maj 10, 2022  03:03
- Sign: Johan.Nylander\@nrm.se

## Description

Script for running (one) "standard" phylogenetic analysis on fasta-formatted input.

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

## Prerequitsites

- BMGE (v1.12): Get from <http://ftp.pasteur.fr/pub/gensoft/projects/BMGE/>
- GNU parallel (v20161222): `sudo apt install parallel`
- ParGenes (v1.3.9): `git clone --recursive https://github.com/BenoitMorel/ParGenes.git ; cd ParGenes ; ./install.sh`
- RAxML-NG (v0.9.0): `wget https://github.com/amkozlov/raxml-ng/releases/download/1.1.0/raxml-ng_v1.1.0_linux_x86_64.zip` (and unzip, rename to raxml-ng and put in your `~/bin`  folder
- TreeShrink (v1.3.9): `git clone https://github.com/uym2/TreeShrink.git ; cd TreeShrink ; python setup.py install --user`
- catfasta2phyml.pl (v1.1.0): `git clone https//github/nylander/catfasta2phyml.git` (and copy `catfasta2phyml.pl` to your path).
- degap_fasta_alignment.pl (v2.0): `wget https://raw.githubusercontent.com/nylander/fastagap/master/degap_fasta_alignment.pl`
- mafft (v7.453): `sudo apt install mafft`
- phylip2fasta.pl (v0.3): `git clone https://github.com/nylander/phy2fas.git` (and copy `phylip2fasta.pl` to your path).

### Important

Currently, paths to some binaries needs to be manually adjusted inside the
[align-and-trees-workflow.sh](src/align-and-trees-workflow.sh) script, as well
as number of available cores!


