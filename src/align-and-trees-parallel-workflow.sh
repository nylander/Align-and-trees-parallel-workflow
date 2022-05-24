#!/bin/bash -l

set -euo pipefail

## Default settings
version="0.1"
quiet=0 # TODO: Use this option
modeltestcriterion="BIC"
datatype='nt'
ncores='8'               # TODO: Adjust. This value needs to be checked againt hardware and threadsforparallel
threadsforparallel='6'   # TODO: Adjust. This value le ncores
modeltestperjobcores='4' # TODO: Adjust. This value needs to be at least 4
bmgejar="/home/nylander/src/BMGE-1.12/BMGE.jar"              # <<<<<<<<<<<<<< CHANGE HERE
pargenes="/home/nylander/src/ParGenes/pargenes/pargenes.py"  # <<<<<<<<<<<<<< CHANGE HERE
treeshrink="/home/nylander/src/TreeShrink/run_treeshrink.py" # <<<<<<<<<<<<<< CHANGE HERE

## Usage
function usage {
cat <<End_Of_Usage

$(basename "$0") version ${version}

What:
           Run phylogenetics in parallel

By:
           Johan Nylander

Usage:
           $(basename "$0") [option] infolder outfolder

Options:
           -d type   -- Specify data type: nt or aa. Default: ${datatype}
           -t number -- Specify the number of threads for xxx. Deafult: ${ncores}
           -m crit   -- Model test criterion: BIC, AIC or AICC. Default: ${modeltestcriterion}
           -q        -- Be quiet (noverbose)
           -v        -- Print version
           -h        -- Print help message

Examples:
           $(basename "$0") infolder outfolder
           $(basename "$0") -d nt -t 8 data out

Input:
           Fasta formatted sequence files
           Text

Output:
           Text

Notes:
           See INSTALL file for needed software


License:   Copyright (C) 2022 nylander <johan.nylander@nrm.se>
           Distributed under terms of the MIT license.

End_Of_Usage

}


### Programs
aligner="mafft" # Name of aligner, not path to binary
alignerbin="mafft"
alignerbinopts=' --auto'
realigner="mafft"
raxmlng="raxml-ng"
fastagap="fastagap.pl"
catfasta2phyml="catfasta2phyml.pl"
phylip2fasta="phylip2fasta.pl"

prog_exists() {
    if ! command -v "$1" &> /dev/null ; then
        echo "## ALIGN-AND-TREES-WORKFLOW: ERROR: $1 could not be found"
        exit 1
    fi
}
export -f prog_exists

for p in \
    "${alignerbin}" \
    "${catfasta2phyml}" \
    "${fastagap}" \
    "${phylip2fasta}" \
    "${raxmlng}" \
    "${realigner}" ; do
    prog_exists "${p}"
done

### Data type

### Model-selection criterion and default models
modelforraxmltest='GTR'
datatypeforbmge='DNA'
modelforpargenesfixed='GTR+G8+F'
if [ "${datatype}" = 'aa' ] ; then
    datatypeforbmge='AA'
    modelforraxmltest='LG'
    modelforpargenesfixed='LG+G8+F'
fi

## Arguments
dflag=
tflag=
mflag=
vflag=
qflag=
hflag=

while getopts 'd:t:m:vqh' OPTION
do
  case $OPTION in
  d) dflag=1
     dval="$OPTARG"
     ;;
  t) tflag=1
     tval="$OPTARG"
     ;;
  m) mflag=1
     mval="$OPTARG"
     ;;
  v) echo "${version}"
     exit
     ;;
  q) qflag=1
     quiet=1
     ;;
  h) usage
     exit
     ;;
  *) usage
     exit
     ;;
  esac
done
shift $((OPTIND - 1))

## Check if args are folders
if [ $# -ne 2 ]; then
    echo 1>&2 "Usage: $0 [options] /path/to/folder/with/fas/files /path/to/output/folder"
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

if [ "${dflag}" ] ; then
    datatype="${dval}"
    # Need to check if 'nt' or 'aa'
fi

if [ "${tflag}" ] ; then
    threads="${tval}"
    ncores="${threads}" # For now
fi

if [ "${mflag}" ] ; then
    modeltestcriterion="${mval}"
    # Need to check if 'BIC', 'AIC', or 'AICC'(?)
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

## Step 1. Alignments with mafft
## TODO: redirect stderr?
echo "## ALIGN-AND-TREES-WORKFLOW: Align with ${aligner}"
mkdir -p "${runfolder}/align/${aligner}"
find "${unaligned}" -type f -name '*.fas' | \
    parallel ''"${alignerbin}"' '"${alignerbinopts}"' {} > '"${runfolder}"'/align/'"${aligner}"'/{/.}.'"${aligner}"'.ali'
    #parallel ''"${alignerbin}"' '"${alignerbinopts}"' {} > '"${runfolder}"'/align/'"${aligner}"'/{/.}.'"${aligner}"'.ali 2> /dev/null'

## Step 2. Check alignments with raxml-ng
## TODO: redirect stderr?
echo '## ALIGN-AND-TREES-WORKFLOW: Check alignments with raxml-ng'
mkdir -p "${runfolder}/align/${aligner}.check"
ln -s -f "${runfolder}/align/${aligner}"/*.ali "${runfolder}/align/${aligner}.check/"
cd "${runfolder}/align/${aligner}.check" || exit
find -L . -type f -name '*.ali' | \
    parallel ''"${raxmlng}"' --check --msa {} --threads 1 --model '"${modelforraxmltest}"' >/dev/null || true'

## Step 3. Find error in logs.
## TODO: remove also the ali file!
cd "${runfolder}/align/${aligner}.check" || exit
echo '## ALIGN-AND-TREES-WORKFLOW: Find error in logs. If error, remove the ali file'
find . -type f -name '*.log' | \
    parallel 'if grep -q "^ERROR" {} ; then echo "found error in {}"; rm -v {=s/\.raxml\.log//=} ; fi'

## Step 4. If no .raxml.reduced.phy file was created, create one
## TODO: Do not use the .reduced.phy alignments! So skip this step. We wish to use all ali files which are not removed above.
cd "${runfolder}/align/${aligner}.check" || exit
echo '## ALIGN-AND-TREES-WORKFLOW: If no .raxml.reduced.phy file was created, create one'
find -L . -type f -name '*.ali' | \
    parallel 'if [ ! -e {}.raxml.reduced.phy ] ; then '"${catfasta2phyml}"' {} 2> /dev/null > {}.raxml.reduced.phy; fi'

## Step 5. Check and remove if any of the .phy files have less than 4 taxa
## TODO: Do not use the .reduced.phy alignments! So skip this step. We wish to use all ali files which are not removed above.
echo '## ALIGN-AND-TREES-WORKFLOW: Check and remove if any of the .reduced.phy files have less than 4 taxa'
find "${runfolder}/align/${aligner}.check/" -type f -name '*.reduced.phy' | \
    parallel checkNtaxaInPhylip

## Step 6. Remove all .ali files in the check directory
## TODO: we actually wish to keep and use the ali files!
echo '## ALIGN-AND-TREES-WORKFLOW: Remove all .ali files in the check directory'
cd "${runfolder}/align/${aligner}.check" || exit
rm ./*.ali ./*.log

## Step 7. Run first run of BMGE
## TODO: Do not use the .reduced.phy alignments! Use the ali files
echo '## ALIGN-AND-TREES-WORKFLOW: Run BMGE'
mkdir -p "${runfolder}/align/bmge"
cd "${runfolder}/align/bmge" || exit
find "${runfolder}/align/${aligner}.check/" -type f -name '*.reduced.phy' | \
    parallel 'java -jar '"${bmgejar}"' -i {} -t '"${datatypeforbmge}"' -o {/.}.bmge.phy'

## Step 8. Check and remove if any of the .bmge.phy files have less than 4 taxa
echo '## ALIGN-AND-TREES-WORKFLOW: Check and remove if any of the .bmge.phy files have less than 4 taxa'
find "${runfolder}/align/bmge" -type f -name '*.phy' | \
    parallel checkNtaxaInPhylip

## Step 9. Run pargenes on the .bmge.phy files with fixed model
echo '## ALIGN-AND-TREES-WORKFLOW: Run first round of pargenes (raxml-ng)'
mkdir -p "${runfolder}/trees"
cd "${runfolder}/trees" || exit
"${pargenes}" \
    --alignments-dir "${runfolder}/align/bmge" \
    --output-dir "${runfolder}/trees/pargenes-bmge" \
    --cores "${ncores}" \
    --datatype "${datatype}" \
    --raxml-global-parameters-string "--model ${modelforpargenesfixed}"

## Step 10. Prepare input for threeshrink
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

## Step 11. Run treeshrink
echo '## ALIGN-AND-TREES-WORKFLOW: Run treeshrink'
"${treeshrink}" \
    --indir "${runfolder}/treeshrink/input-bmge" \
    --tree 'raxml.bestTree' \
    --alignment "${aligner}.ali"

## Step 12. Check and remove if any of the output.ali files have less than 4 taxa
echo '## ALIGN-AND-TREES-WORKFLOW: Check and remove if any of the output.ali files from treeshrink have less than 4 taxa'
find "${runfolder}/treeshrink/input-bmge" -type f -name 'output.ali' | \
    parallel checkNtaxaInFasta

## Step 13. Realign using realigner
echo '## ALIGN-AND-TREES-WORKFLOW: Realign using realigner'
mkdir -p "${runfolder}/treeshrink/realign-bmge"
find "${runfolder}/treeshrink/input-bmge/" -type f -name 'output.ali' | \
    parallel 'b=$(basename {//} .ali); '"${realigner}"' --auto --thread '"${threadsforparallel}"' <('"${fastagap}"' {}) > '"${runfolder}"'/treeshrink/realign-bmge/"${b//_/\.}.ali"'

## Step 14. Run pargenes again, finish with ASTRAL
echo '## ALIGN-AND-TREES-WORKFLOW: Run pargenes again, finish with ASTRAL'
"${pargenes}" \
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

