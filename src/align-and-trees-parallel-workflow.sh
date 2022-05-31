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
        echo -e "\n## ALIGN-AND-TREES-WORKFLOW: ERROR: $1 could not be found"
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
        echo -e "\n## ALIGN-AND-TREES-WORKFLOW: Found .fas files in folder ${unaligned}"
    else
        echo -e "\n## ALIGN-AND-TREES-WORKFLOW: ERROR: Could not find .fas files in folder ${unaligned}"
        exit 1
    fi
else
    echo -e "\n## ALIGN-AND-TREES-WORKFLOW: ERROR: folder ${unaligned} can not be found"
    exit 1
fi

if [ -d "${runfolder}" ]; then
    echo -e "\n## ALIGN-AND-TREES-WORKFLOW: ERROR: folder ${runfolder} exists"
    exit 1
else
    mkdir -p "${runfolder}"
    echo -e "\n## ALIGN-AND-TREES-WORKFLOW: Created output folder ${runfolder}"
fi

if [ "${dflag}" ] ; then
    datatype="${dval}"
    ## TODO: Need to check if 'nt' or 'aa'
fi

if [ "${tflag}" ] ; then
    threads="${tval}"
    ncores="${threads}" # TODO: differentiate these variables
fi

if [ "${mflag}" ] ; then
    modeltestcriterion="${mval}"
    ## TODO: Need to check if 'BIC', 'AIC', or 'AICC'(?)
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

######################################################################################
## Step 1. Alignments with mafft
## Input: inputfolder/*.fas
## Output: 1_align/1.1_mafft/*.mafft.ali
## TODO: redirect stderr?
echo -e "\n## ALIGN-AND-TREES-WORKFLOW: Align with ${aligner}"
mkdir -p "${runfolder}/1_align/1.1_${aligner}"
find "${unaligned}" -type f -name '*.fas' | \
    parallel ''"${alignerbin}"' '"${alignerbinopts}"' {} > '"${runfolder}"'/1_align/1.1_'"${aligner}"'/{/.}.'"${aligner}"'.ali'


######################################################################################
## Step 2. Check alignments with raxml-ng
## Input: 1_align/1.2_mafft_check/*.mafft.ali
## Output: 1_align/1.2_mafft_check/*.mafft.ali.raxml.log, and, sometimes, 1_align/1.2_mafft_check/*.mafft.ali.raxml.reduced.phy
## TODO: redirect stderr?
echo -e '\n## ALIGN-AND-TREES-WORKFLOW: Check alignments with raxml-ng'
mkdir -p "${runfolder}/1_align/1.2_${aligner}_check"
ln -s -f "${runfolder}/1_align/1.1_${aligner}"/*.ali "${runfolder}/1_align/1.2_${aligner}_check/"
cd "${runfolder}/1_align/1.2_${aligner}_check" || exit
find -L . -type f -name '*.ali' | \
    parallel ''"${raxmlng}"' --check --msa {} --threads 1 --model '"${modelforraxmltest}"' >/dev/null || true'


######################################################################################
## Step 3. Find error in logs.
## Input: 1_align/1.2_mafft.check/*.mafft.ali.raxml.log
## Output: removes 1_align/1.2_mafft.check/*.mafft.ali if error
## TODO: 
cd "${runfolder}/1_align/1.2_${aligner}_check" || exit
echo -e '\n## ALIGN-AND-TREES-WORKFLOW: Find error in logs. If error, remove the ali file'
find . -type f -name '*.log' | \
    parallel 'if grep -q "^ERROR" {} ; then echo "found error in {}"; rm -v {=s/\.raxml\.log//=} ; fi'


######################################################################################
## Step 4. Remove all .ali files in the check directory
## Input: folder 1_align/1.2_mafft_check
## Output: Removes *.log *.raxml.reduced.phy
## TODO: we actually wish to keep and use the ali files!
echo -e '\n## ALIGN-AND-TREES-WORKFLOW: Remove all .ali files in the check directory'
cd "${runfolder}/1_align/1.2_${aligner}_check" || exit
rm ./*.log ./*.raxml.reduced.phy


######################################################################################
## Step 5. Run first run of BMGE
## Input: 1_align/1.2_mafft_check/*.mafft.ali (symlinks)
## Output: 1_align/1.3_mafft_check_bmge/*.bmge.ali
## TODO:
echo -e '\n## ALIGN-AND-TREES-WORKFLOW: Run BMGE'
mkdir -p "${runfolder}/1_align/1.3_mafft_check_bmge"
cd "${runfolder}/1_align/1.3_mafft_check_bmge" || exit
find -L "${runfolder}/1_align/1.2_${aligner}_check/" -type f -name '*.ali' | \
    parallel 'java -jar '"${bmgejar}"' -i {} -t '"${datatypeforbmge}"' -of {/.}.bmge.ali'


######################################################################################
## Step 6. Check and remove if any of the .mafft.bmge.ali files have less than 4 taxa
## Input: 1_align/1.3_mafft_check_bmge/*.mafft.bmge.ali
## Output: remove /1_align/1.3_mafft_check_bmge/*.mafft.bmge.ali files
## TODO:
echo -e '\n## ALIGN-AND-TREES-WORKFLOW: Check and remove if any of the .bmge.phy files have less than 4 taxa'
find "${runfolder}/1_align/1.3_mafft_check_bmge" -type f -name '*.ali' | \
    parallel checkNtaxaInFasta


######################################################################################
## Step 7. Run pargenes on the .bmge.ali files with fixed model
## Input: /1_align/1.3_mafft_check_bmge
## Output: /2_trees/2.1_mafft_check_bmge_pargenes
## TODO:
echo -e '\n## ALIGN-AND-TREES-WORKFLOW: Run first round of pargenes (raxml-ng)'
mkdir -p "${runfolder}/2_trees"
cd "${runfolder}/2_trees" || exit
"${pargenes}" \
    --alignments-dir "${runfolder}/1_align/1.3_mafft_check_bmge" \
    --output-dir "${runfolder}/2_trees/2.1_mafft_check_bmge_pargenes" \
    --cores "${ncores}" \
    --datatype "${datatype}" \
    --raxml-global-parameters-string "--model ${modelforpargenesfixed}"


######################################################################################
## Step 8. Prepare input for threeshrink
## Input: 1_align/1.3_mafft_check_bmge/*.bmge.ali
## Output: 3_treeshrink/3.1_input-bmge/EOG7B0H2N_mafft_bmge_ali/mafft.ali
## TODO: 
echo -e '\n## ALIGN-AND-TREES-WORKFLOW: Prepare input for threeshrink'
mkdir -p "${runfolder}/3_treeshrink/3.1_treeshrink"
copyAndConvert () {
    f=$(basename "$1") # f=EOG7B0H2N.mafft.bmge.ali
    s="${f//\./_}"     # s=EOG7B0H2N_mafft_bmge_ali
    mkdir -p "${runfolder}/3_treeshrink/3.1_treeshrink/${s}"
    ln -s "${runfolder}/2_trees/2.1_mafft_check_bmge_pargenes/mlsearch_run/results/${s}/${s}.raxml.bestTree" "${runfolder}/3_treeshrink/3.1_treeshrink/${s}/raxml.bestTree"
    ln -s "${runfolder}/1_align/1.3_mafft_check_bmge/${f}" "${runfolder}/3_treeshrink/3.1_treeshrink/${s}/${aligner}.ali"
}
export -f copyAndConvert
find "${runfolder}/1_align/1.3_mafft_check_bmge/" -type f -name '*.bmge.ali' | \
    parallel copyAndConvert


######################################################################################
## Step 9. Run treeshrink
## Input: 3_treeshrink/3.1_input-bmge
## Output: 
## TODO:
echo -e '\n## ALIGN-AND-TREES-WORKFLOW: Run treeshrink'
"${treeshrink}" \
    --indir "${runfolder}/3_treeshrink/3.1_treeshrink" \
    --tree 'raxml.bestTree' \
    --alignment "${aligner}.ali"


######################################################################################
## Step 10. Check and remove if any of the output.ali files have less than 4 taxa
## Input: 3_treeshrink/3.1_input-bmge
## Output: remove output.ali files
## TODO:
echo -e '\n## ALIGN-AND-TREES-WORKFLOW: Check and remove if any of the output.ali files from treeshrink have less than 4 taxa'
find "${runfolder}/3_treeshrink/3.1_treeshrink" -type f -name 'output.ali' | \
    parallel checkNtaxaInFasta


######################################################################################
## Step 11. Realign using realigner
## Input: 3_treeshrink/3.1_input-bmge/
## Output: 1_align/1.4_mafft_check_bmge_treeshrink
## TODO:
echo -e '\n## ALIGN-AND-TREES-WORKFLOW: Realign after treeshrink using realigner'
mkdir -p "${runfolder}/1_align/1.4_mafft_check_bmge_treeshrink"
find "${runfolder}/3_treeshrink/3.1_treeshrink/" -type f -name 'output.ali' | \
    parallel 'b=$(basename {//} .ali); '"${realigner}"' --auto --thread '"${threadsforparallel}"' <('"${fastagap}"' {}) > '"${runfolder}"'/1_align/1.4_mafft_check_bmge_treeshrink/"${b//_/\.}"'


######################################################################################
## Step 12. Run pargenes again, finish with ASTRAL
## Input: 1_align/1.4_mafft_check_bmge_treeshrink/*.mafft.bmge.ali
## Output: 2_trees/2.2_mafft_check_bmge_treeshrink_pargenes
## TODO:
echo -e "\n## ALIGN-AND-TREES-WORKFLOW: Run pargenes again, finish with ASTRAL"
"${pargenes}" \
    --alignments-dir "${runfolder}/1_align/1.4_mafft_check_bmge_treeshrink" \
    --output-dir "${runfolder}/2_trees/2.2_mafft_check_bmge_treeshrink_pargenes" \
    --cores "${ncores}" \
    --datatype "${datatype}" \
    --use-modeltest \
    --modeltest-criteria "${modeltestcriterion}" \
    --modeltest-perjob-cores "${modeltestperjobcores}" \
    --use-astral


######################################################################################
## End
echo -e "\n## ALIGN-AND-TREES-WORKFLOW: Reached end of trees script."
echo -e "\n## ALIGN-AND-TREES-WORKFLOW: Final species tree should be in folder:"
echo -e "\n## ALIGN-AND-TREES-WORKFLOW: ${runfolder}/2_trees/2.2_mafft_check_bmge_treeshrink_pargenes/astral_run"
tree "${runfolder}/2_trees/2.2_mafft_check_bmge_treeshrink_pargenes/astral_run"

exit 0

