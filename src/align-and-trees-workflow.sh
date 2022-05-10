#!/bin/bash -l

## File: align-and-trees-workflow.sh
## Last modified: tis maj 10, 2022  03:00
## Sign: JN
##
## Description:
##     On unfiltered fasta files, run
##     aligner + BMGE + pargenes + treeshrink + realigner + pargenes + ASTRAL
##
## Usage:
##     ./align-and-trees-workflow.sh /path/to/folder/with/fas/files /path/to/new/run/folder
##
## Prerequitsites:
##     Unaligned aa or nt sequences (need to specify manually) in fasta formatted files,
##     one per locus, placed in the folder which is the first argument to the script.
##     Name example: EOG7CKDX2.fas. The part 'EOG7CKDX2' will be used
##     as locus name in downstream analyses.
##
##   Program versions used:
##       BMGE v1.12
##       GNU parallel v20161222
##       catfasta2phyml.pl v1.1.0
##       degap_fasta_alignment.pl v2.0
##       mafft v7.453
##       pargenes v1.3.9
##       phylip2fasta.pl v0.3
##       raxml-ng v0.9.0
##       treeshrink v1.3.9
##
## Important:
##     Paths to some binaries needs to be adjusted, as well as number of
##     available cores!
##

set -euo pipefail

## Settings and programs

#### Compute resources
ncores='10'                  # <<<<<<<<<<<<<< CHANGE HERE
threadsforparallel='8'       # <<<<<<<<<<<<<< CHANGE HERE
modeltestperjobcores='4'     # <<<<<<<<<<<<<< CHANGE HERE

#### Data type
datatype='nt' # 'aa' or 'nt' # <<<<<<<<<<<<<< CHANGE HERE

#### Model-selection criterion and default models
modeltestcriterion='BIC'
modelforraxmltest='GTR'
datatypeforbmge='DNA'
modelforpargenesfixed='GTR+G8+F'
if [ "${datatype}" = 'aa' ] ; then
    datatypeforbmge='AA'
    modelforraxmltest='LG'
    modelforpargenesfixed='LG+G8+F'
fi

#### Programs
pargenes='/home/nylander/src/ParGenes/pargenes/pargenes.py'  # <<<<<<<<<<<<<< CHANGE HERE
treeshrink='/home/nylander/src/TreeShrink/run_treeshrink.py' # <<<<<<<<<<<<<< CHANGE HERE
bmgejar='/home/nylander/src/BMGE-1.12/BMGE.jar'              # <<<<<<<<<<<<<< CHANGE HERE
aligner='mafft'
alignerbinopts=' --auto'
export aligner

prog_exists() {
    if ! command -v "$1" &> /dev/null ; then
        echo "## ALIGN-AND-TREES-WORKFLOW: ERROR: $1 could not be found"
        exit 1
    fi
}
export -f prog_exists

for p in "mafft" "raxml-ng" "degap_fasta_alignment.pl" "catfasta2phyml.pl" "phylip2fasta.pl" ; do
    prog_exists "${p}"
done

for p in "${bmgejar}" "${pargenes}" "${treeshrink}" ; do
    if [ ! -f "${p}" ] ; then
        echo "## ALIGN-AND-TREES-WORKFLOW: ERROR: ${p} could not be found"
        exit 1
    fi
done

alignerbin=$(command -v "${aligner}")
realigner=$(command -v mafft)
raxmlng=$(command -v raxml-ng)
degap_fasta_alignment=$(command -v degap_fasta_alignment.pl)
catfasta2phyml=$(command -v catfasta2phyml.pl)
phylip2fasta=$(command -v phylip2fasta.pl)


## Arguments: 1) unaligned seqs folder and 2) run folder
if [ $# -ne 2 ]; then
    echo 1>&2 "Usage: $0 /path/to/folder/with/fas/files /path/to/new/run/folder"
    exit 1
else
    unaligned=$(readlink -f "$1")
    runfolder=$(readlink -f "$2")
fi

if [ -d "${unaligned}" ] ; then
    if [ "$(find "${unaligned}" -name '*.fas' | wc -l)" -gt 1 ] ; then
        echo "## ALIGN-AND-TREES-WORKFLOW: Found .fas files in folder ${unaligned}"
    else
        echo "## ALIGN-AND-TREES-WORKFLOW: ERROR: Could not find .fas files in folder ${unaligned}"
        exit 1
    fi
else
    echo "## ALIGN-AND-TREES-WORKFLOW: ERROR: folder ${unaligned} can not be found"
    exit 1
fi

if [ -d "${runfolder}" ]; then
    echo "## ALIGN-AND-TREES-WORKFLOW: ERROR: folder ${runfolder} exists"
    exit 1
else
    mkdir -p "${runfolder}"
    echo "## ALIGN-AND-TREES-WORKFLOW: Created output folder ${runfolder}"
fi

## Needed for some bash functions
export runfolder
export phylip2fasta
export aligner

## Function for checking and removing phylip files with less than N taxa
## If other max N, use, e.g., "parallel checkNtaxaInPhylip {} 10"
checkNtaxaInPhylip() {
    f=$1
    n=${2:-4} # default 4
    b=$(basename "${f}")
    ntax=$(grep -m1 -oP '\K\d+(?=\s)' "${f}")
    if [[ "${ntax}" -lt $n ]] ; then
        echo -e "${b} have less than ${n} taxa: (${ntax})."
        rm -v "${f}"
    fi
}
export -f checkNtaxaInPhylip

## Function for checking and removing fasta files with less than N taxa
## If other max N, use, e.g., "parallel checkNtaxaInFasta {} 10"
checkNtaxaInFasta() {
    f=$1
    n=${2:-4} # default 4
    b=$(basename "${f}")
    ntax=$(grep -c '>' "${f}")
    if [[ "${ntax}" -lt $n ]] ; then
        echo -e "${b} have less than ${n} taxa: (${ntax})."
        rm -v "${f}"
    fi
}
export -f checkNtaxaInFasta

## Alignments with mafft
echo "## ALIGN-AND-TREES-WORKFLOW: Align with ${aligner}"
mkdir -p "${runfolder}/align/${aligner}"
find "${unaligned}" -type f -name '*.fas' | \
    parallel ''"${alignerbin}"' '"${alignerbinopts}"' {} > '"${runfolder}"'/align/'"${aligner}"'/{/.}.'"${aligner}"'.ali'

## Check alignments with raxml-ng
echo '## ALIGN-AND-TREES-WORKFLOW: Check alignments with raxml-ng'
mkdir -p "${runfolder}/align/${aligner}.check"
ln -s -f "${runfolder}/align/${aligner}"/*.ali "${runfolder}/align/${aligner}.check/"
cd "${runfolder}/align/${aligner}.check" || exit
find -L . -type f -name '*.ali' | \
    parallel ''"${raxmlng}"' --check --msa {} --model '"${modelforraxmltest}"' >/dev/null || true'

## Find error in logs. If error, remove the ali file
cd "${runfolder}/align/${aligner}.check" || exit
echo '## ALIGN-AND-TREES-WORKFLOW: Find error in logs. If error, remove the ali file'
find . -type f -name '*.log' | \
    parallel 'if grep -q "^ERROR" {} ; then echo "found error in {}"; rm -v {=s/\.raxml\.log//=} ; fi'

## If no .raxml.reduced.phy file was created, create one
cd "${runfolder}/align/${aligner}.check" || exit
echo '## ALIGN-AND-TREES-WORKFLOW: If no .raxml.reduced.phy file was created, create one'
find -L . -type f -name '*.ali' | \
    parallel 'if [ ! -e {}.raxml.reduced.phy ] ; then '"${catfasta2phyml}"' {} 2> /dev/null > {}.raxml.reduced.phy; fi'

## Check and remove if any of the .phy files have less than 4 taxa
echo '## ALIGN-AND-TREES-WORKFLOW: Check and remove if any of the .reduced.phy files have less than 4 taxa'
find "${runfolder}/align/${aligner}.check/" -type f -name '*.reduced.phy' | \
    parallel checkNtaxaInPhylip

## Remove all .ali files in the check directory
echo '## ALIGN-AND-TREES-WORKFLOW: Remove all .ali files in the check directory'
cd "${runfolder}/align/${aligner}.check" || exit
rm ./*.ali ./*.log

## Run first run of BMGE
echo '## ALIGN-AND-TREES-WORKFLOW: Run BMGE'
mkdir -p "${runfolder}/align/bmge"
cd "${runfolder}/align/bmge" || exit
find "${runfolder}/align/${aligner}.check/" -type f -name '*.reduced.phy' | \
    parallel 'java -jar '"${bmgejar}"' -i {} -t '"${datatypeforbmge}"' -o {/.}.bmge.phy'

## Check and remove if any of the .bmge.phy files have less than 4 taxa
echo '## ALIGN-AND-TREES-WORKFLOW: Check and remove if any of the .bmge.phy files have less than 4 taxa'
find "${runfolder}/align/bmge" -type f -name '*.phy' | \
    parallel checkNtaxaInPhylip

## Run pargenes on the .bmge.phy files with fixed model
echo '## ALIGN-AND-TREES-WORKFLOW: Run first round of pargenes (raxml-ng)'
mkdir -p "${runfolder}/trees"
cd "${runfolder}/trees" || exit
python "${pargenes}" \
    --alignments-dir "${runfolder}/align/bmge" \
    --output-dir "${runfolder}/trees/pargenes-bmge" \
    --cores "${ncores}" \
    --datatype "${datatype}" \
    --raxml-global-parameters-string "--model ${modelforpargenesfixed}"
#    --use-modeltest \
#    --modeltest-criteria "${modeltestcriterion}" \
#    --modeltest-perjob-cores "${modeltestperjobcores}"

## Prepare input for threeshrink
echo '## ALIGN-AND-TREES-WORKFLOW: Prepare input for threeshrink'
mkdir -p "${runfolder}/treeshrink/input-bmge"
copyAndConvert () {
    f=$(basename "$1") # f=EOG7FC368.mafft.ali.raxml.reduced.bmge.phy
    s="${f//\./_}"   # s=EOG7FC368_mafft_ali_raxml_reduced_bmge_phy
    mkdir -p "${runfolder}/treeshrink/input-bmge/${s}"
    cp "${runfolder}/trees/pargenes-bmge/mlsearch_run/results/${s}/${s}.raxml.bestTree" "${runfolder}/treeshrink/input-bmge/${s}/raxml.bestTree"
    "${phylip2fasta}" -i "${runfolder}/align/bmge/${f}" -o "${runfolder}/treeshrink/input-bmge/${s}/${aligner}.ali"
}
export -f copyAndConvert
find "${runfolder}/align/bmge/" -type f -name '*.bmge.phy' | \
    parallel copyAndConvert

## Run treeshrink
echo '## ALIGN-AND-TREES-WORKFLOW: Run treeshrink'
python "${treeshrink}" \
    --indir "${runfolder}/treeshrink/input-bmge" \
    --tree 'raxml.bestTree' \
    --alignment "${aligner}.ali"

## Check and remove if any of the output.ali files have less than 4 taxa
echo '## ALIGN-AND-TREES-WORKFLOW: Check and remove if any of the output.ali files from treeshrink have less than 4 taxa'
find "${runfolder}/treeshrink/input-bmge" -type f -name 'output.ali' | \
    parallel checkNtaxaInFasta

## Realign using realigner
echo '## ALIGN-AND-TREES-WORKFLOW: Realign using realigner'
mkdir -p "${runfolder}/treeshrink/realign-bmge"
find "${runfolder}/treeshrink/input-bmge/" -type f -name 'output.ali' | \
    parallel 'b=$(basename {//} .ali); '"${realigner}"' --auto --thread '"${threadsforparallel}"' <('"${degap_fasta_alignment}"' --all {}) > '"${runfolder}"'/treeshrink/realign-bmge/"${b//_/\.}.ali"'

## Another round of BMGE?
#

## Run pargenes again, finish with ASTRAL
echo '## ALIGN-AND-TREES-WORKFLOW: Run pargenes again, finish with ASTRAL'
python "${pargenes}" \
    --alignments-dir "${runfolder}/treeshrink/realign-bmge" \
    --output-dir "${runfolder}/trees/pargenes-bmge-treeshrink" \
    --cores "${ncores}" \
    --datatype "${datatype}" \
    --use-modeltest \
    --modeltest-criteria "${modeltestcriterion}" \
    --modeltest-perjob-cores "${modeltestperjobcores}" \
    --use-astral

## End
echo "## ALIGN-AND-TREES-WORKFLOW: Reached end of trees script."
echo "## ALIGN-AND-TREES-WORKFLOW: Final species tree should be in folder:"
echo -e "## ALIGN-AND-TREES-WORKFLOW: ${runfolder}/trees/pargenes-bmge-treeshrink/astral_run"
tree "${runfolder}/trees/pargenes-bmge-treeshrink/astral_run"

