#!/bin/bash -l

set -euo pipefail

## Default settings
version="0.3"
quiet=0 # TODO: Use this option
logfile=
modeltestcriterion="BIC"
datatype='nt'

nprocs=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null)
ncores="${nprocs}"        # TODO: Do we need to adjust?
#threadsforparallel='6'   # TODO: Adjust? This value less or equal to ncores?
modeltestperjobcores='4'  # TODO: Adjust? This value needs to be at least 4!
threadsforaligner='2'     # TODO: Adjust?
threadsforrealigner='2'   # TODO: Adjust?

bmgejar="/home/nylander/src/BMGE-1.12/BMGE.jar"              # <<<<<<<<<< CHANGE HERE
pargenes="/home/nylander/src/ParGenes/pargenes/pargenes.py"  # <<<<<<<<<< CHANGE HERE
treeshrink="/home/nylander/src/TreeShrink/run_treeshrink.py" # <<<<<<<<<< CHANGE HERE

aligner="mafft" # Name of aligner, not path to binary
alignerbin="mafft"
alignerbinopts=" --auto --thread ${threadsforaligner} --quiet"
realigner="mafft" # Name of realigner, not path to binary
realignerbinopts="${alignerbinopts}"

raxmlng="raxml-ng"
fastagap="fastagap.pl"
catfasta2phyml="catfasta2phyml.pl"
phylip2fasta="phylip2fasta.pl"


## Usage
function usage {
cat <<End_Of_Usage

$(basename "$0") version ${version}

What:
           Phylogenetics in parallel

By:
           Johan Nylander

Usage:
           $(basename "$0") [option] infolder outfolder

Options:
           -d type   -- Specify data type: nt or aa. Default: ${datatype}
           -t number -- Specify the number of threads. Deafult: ${ncores}
           -m crit   -- Model test criterion: BIC, AIC or AICC. Default: ${modeltestcriterion}
           -v        -- Print version
           -h        -- Print help message

Examples:
           $(basename "$0") infolder outfolder
           $(basename "$0") -d nt -t 8 data out

Input:
           Folder with fasta formatted sequence files (files need to have suffix ".fas")

Output:
           Folders with filtered alignments and species- and gene-trees.
           Summary README.md file.
           Log file.

Notes:
           See INSTALL file for software needed.


License:   Copyright (C) 2022 nylander <johan.nylander@nrm.se>
           Distributed under terms of the MIT license.

End_Of_Usage

}


## Check programs
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


## Model-selection criterion and default models
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
hflag=

while getopts 'd:t:m:vh' OPTION
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
  h) usage
     exit
     ;;
  *) usage
     exit
     ;;
  esac
done
shift $((OPTIND - 1))


## Check if args are folders and create log file
if [ $# -ne 2 ]; then
    echo 1>&2 "Usage: $0 [options] /path/to/folder/with/fas/files /path/to/output/folder"
    exit 1
else
    unaligned=$(readlink -f "$1")
    runfolder=$(readlink -f "$2")
fi

if [ -d "${runfolder}" ]; then
    echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! folder ${runfolder} exists"
    exit 1
else
    mkdir -p "${runfolder}"
    logfile="${runfolder}/align-and-trees-parallel-workflow.log"
    echo -e "\n## ATPW [$(date "+%F %T")]: Start" 2>&1 | tee "${logfile}"
    echo -e "\n## ATPW [$(date "+%F %T")]: Created output folder ${runfolder}" 2>&1 | tee "${logfile}"
fi

if [ -d "${unaligned}" ] ; then
    if [ "$(find "${unaligned}" -name '*.fas' | wc -l)" -gt 1 ] ; then
        echo -e "\n## ATPW [$(date "+%F %T")]: Found .fas files in folder ${unaligned}" 2>&1 | tee "${logfile}"
    else
        echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! Could not find .fas files in folder ${unaligned}" 2>&1 | tee "${logfile}"
        exit 1
    fi
else
    echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! Folder ${unaligned} can not be found" 2>&1 | tee "${logfile}"
    exit 1
fi


## Check options
if [ "${dflag}" ] ; then
    lcdval=${dval,,} # to lowercase
    if [[ "${lcdval}" != @(nt|aa) ]] ; then
        echo "\n## ATPW [$(date "+%F %T")]: ERROR! -d should be 'nt' or 'aa'" 2>&1 | tee "${logfile}"
    else
        datatype="${lcdval}"
    fi
fi

if [ "${tflag}" ] ; then
    threads="${tval}"
    ncores="${threads}" # TODO: differentiate these variables
fi

if [ "${mflag}" ] ; then
    lcmval=${mval,,} # to lowercase
    if [[ "${lcdval}" != @(bic|aic|aicc) ]] ; then
        echo "\n## ATPW [$(date "+%F %T")]: ERROR! -m should be 'bic', 'aic', or 'aicc'" 2>&1 | tee "${logfile}"
    else
        modeltestcriterion="${lcmval}"
    fi
fi


## Needed for some bash functions
## TODO: Double check which are needed
export runfolder
export phylip2fasta
export aligner
export realigner


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
## TODO: use threads
echo -e "\n## ATPW [$(date "+%F %T")]: Align with ${aligner}" 2>&1 | tee -a "${logfile}"
mkdir -p "${runfolder}/1_align/1.1_${aligner}"
find "${unaligned}" -type f -name '*.fas' | \
    parallel ''"${alignerbin}"' '"${alignerbinopts}"' {} > '"${runfolder}"'/1_align/1.1_'"${aligner}"'/{/.}.'"${aligner}"'.ali' >> "${logfile}" 2>&1


######################################################################################
## Step 2. Check alignments with raxml-ng
## Input: 1_align/1.2_mafft_check/*.mafft.ali
## Output: 1_align/1.2_mafft_check/*.mafft.ali.raxml.log, and, sometimes, 1_align/1.2_mafft_check/*.mafft.ali.raxml.reduced.phy
## TODO: redirect to logfile?
echo -e "\n## ATPW [$(date "+%F %T")]: Check alignments with raxml-ng" | tee -a "${logfile}"
mkdir -p "${runfolder}/1_align/1.2_${aligner}_check"
ln -s -f "${runfolder}/1_align/1.1_${aligner}"/*.ali "${runfolder}/1_align/1.2_${aligner}_check/"
cd "${runfolder}/1_align/1.2_${aligner}_check" || exit
find -L . -type f -name '*.ali' | \
    parallel ''"${raxmlng}"' --check --msa {} --threads 1 --model '"${modelforraxmltest}"'' >> "${logfile}" 2>&1


######################################################################################
## Step 3. Find error in logs.
## Input: 1_align/1.2_mafft.check/*.mafft.ali.raxml.log
## Output: removes 1_align/1.2_mafft.check/*.mafft.ali if error
## TODO: redirect stderr? 
cd "${runfolder}/1_align/1.2_${aligner}_check" || exit
echo -e "\n## ATPW [$(date "+%F %T")]: Look for error in logs. If error, remove the ali file"
find . -type f -name '*.log' | \
    parallel 'if grep -q "^ERROR" {} ; then echo "## ATPW: Found error in {}"; rm -v {=s/\.raxml\.log//=} ; fi' >> "${logfile}" 2>&1
rm ./*.log ./*.raxml.reduced.phy


######################################################################################
## Step 4. Run first run of BMGE
## Input: 1_align/1.2_mafft_check/*.mafft.ali (symlinks)
## Output: 1_align/1.3_mafft_check_bmge/*.bmge.ali
## TODO:
echo -e "\n## ATPW [$(date "+%F %T")]: Run BMGE" | tee -a "${logfile}"
mkdir -p "${runfolder}/1_align/1.3_mafft_check_bmge"
cd "${runfolder}/1_align/1.3_mafft_check_bmge" || exit
find -L "${runfolder}/1_align/1.2_${aligner}_check/" -type f -name '*.ali' | \
    parallel 'java -jar '"${bmgejar}"' -i {} -t '"${datatypeforbmge}"' -of {/.}.bmge.ali' >> "${logfile}" 2>&1


######################################################################################
## Step 5. Check and remove if any of the .mafft.bmge.ali files have less than 4 taxa
## Input: 1_align/1.3_mafft_check_bmge/*.mafft.bmge.ali
## Output: remove /1_align/1.3_mafft_check_bmge/*.mafft.bmge.ali files
## TODO:
echo -e "\n## ATPW [$(date "+%F %T")]: Check and remove if any of the files from BMGE have less than 4 taxa" 2>&1 | tee -a "${logfile}"
find "${runfolder}/1_align/1.3_mafft_check_bmge" -type f -name '*.ali' | \
    parallel checkNtaxaInFasta >> "${logfile}" 2>&1


######################################################################################
## Step 6. Run pargenes on the .bmge.ali files with fixed model
## Input: /1_align/1.3_mafft_check_bmge
## Output: /2_trees/2.1_mafft_check_bmge_pargenes
## TODO:
echo -e "\n## ATPW [$(date "+%F %T")]: Run first round of pargenes" 2>&1 | tee -a "${logfile}"
mkdir -p "${runfolder}/2_trees"
cd "${runfolder}/2_trees" || exit
"${pargenes}" \
    --alignments-dir "${runfolder}/1_align/1.3_mafft_check_bmge" \
    --output-dir "${runfolder}/2_trees/2.1_mafft_check_bmge_pargenes" \
    --cores "${ncores}" \
    --datatype "${datatype}" \
    --raxml-global-parameters-string "--model ${modelforpargenesfixed}" >> "${logfile}" 2>&1


######################################################################################
## Step 7. Run treeshrink. First prepare the folder structure needed
## Input: 3_treeshrink/3.1_treeshrink
## Output: 3_treeshrink/3.1_treeshrink/*/output.ali
## TODO: describe output
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
    parallel copyAndConvert >> "${logfile}" 2>&1
echo -e "\n## ATPW [$(date "+%F %T")]: Run treeshrink" 2>&1 | tee -a "${logfile}"
"${treeshrink}" \
    --indir "${runfolder}/3_treeshrink/3.1_treeshrink" \
    --tree 'raxml.bestTree' \
    --alignment "${aligner}.ali" >> "${logfile}" 2>&1


######################################################################################
## Step 8. Check and remove if any of the output.ali files have less than 4 taxa
## Input: 3_treeshrink/3.1_input-bmge
## Output: remove output.ali files
## TODO:
echo -e "\n## ATPW [$(date "+%F %T")]: Check and remove if any of the files from treeshrink have less than 4 taxa" 2>&1 | tee -a "${logfile}"
find "${runfolder}/3_treeshrink/3.1_treeshrink" -type f -name 'output.ali' | \
    parallel checkNtaxaInFasta >> "${logfile}" 2>&1


######################################################################################
## Step 9. Realign using realigner
## Input: 3_treeshrink/3.1_input-bmge/
## Output: 1_align/1.4_mafft_check_bmge_treeshrink
## TODO:
echo -e "\n## ATPW [$(date "+%F %T")]: Realign after treeshrink using ${realigner}" 2>&1 | tee -a "${logfile}"
mkdir -p "${runfolder}/1_align/1.4_mafft_check_bmge_treeshrink"
find "${runfolder}/3_treeshrink/3.1_treeshrink/" -type f -name 'output.ali' | \
    parallel 'b=$(basename {//} .ali); '"${realigner}"' '"${realignerbinopts}"'  <('"${fastagap}"' {}) > '"${runfolder}"'/1_align/1.4_mafft_check_bmge_treeshrink/"${b//_/\.}"' >> "${logfile}" 2>&1


######################################################################################
## Step 10. Run pargenes again, finish with ASTRAL
## Input: 1_align/1.4_mafft_check_bmge_treeshrink/*.mafft.bmge.ali
## Output: 2_trees/2.2_mafft_check_bmge_treeshrink_pargenes
## TODO:
echo -e "\n## ATPW [$(date "+%F %T")]: Run pargenes again, finish with ASTRAL" 2>&1 | tee -a "${logfile}"
"${pargenes}" \
    --alignments-dir "${runfolder}/1_align/1.4_mafft_check_bmge_treeshrink" \
    --output-dir "${runfolder}/2_trees/2.2_mafft_check_bmge_treeshrink_pargenes" \
    --cores "${ncores}" \
    --datatype "${datatype}" \
    --use-modeltest \
    --modeltest-criteria "${modeltestcriterion}" \
    --modeltest-perjob-cores "${modeltestperjobcores}" \
    --use-astral >> "${logfile}" 2>&1


######################################################################################
## Step 11. Count genes and sequences after each step
## Input:
## Output:
## TODO:
## Count files and sequences in unaligned
nf_unaligned=$(find "${unaligned}" -name '*.fas' | wc -l)
ns_unaligned=$(grep -c -h '>' "${unaligned}"/*.fas | awk '{sum=sum+$1}END{print sum}')
nt_unaligned=$(grep -h '>' "${unaligned}"/*.fas | sort -u | wc -l)

## Count files and sequences in 1.1_mafft
nf_mafft=$(find  "${runfolder}/1_align/1.1_${aligner}" -name '*.ali' | wc -l)
ns_mafft=$(grep -c -h '>' "${runfolder}/1_align/1.1_${aligner}"/*.ali | awk '{sum=sum+$1}END{print sum}')
nt_mafft=$(grep -h '>' "${runfolder}/1_align/1.1_${aligner}"/*.ali | sort -u | wc -l)

## Count files and sequences in 1.2_mafft_check
nf_mafft_check=$(find -L "${runfolder}/1_align/1.2_${aligner}_check" -name '*.ali' | wc -l)
ns_mafft_check=$(grep -c -h '>' "${runfolder}/1_align/1.2_${aligner}_check"/*.ali | awk '{sum=sum+$1}END{print sum}')
nt_mafft_check=$(grep -h '>' "${runfolder}/1_align/1.2_${aligner}_check"/*.ali | sort -u | wc -l)

## Count files and sequences in 1.3_mafft_check_bmge
nf_mafft_check_bmge=$(find "${runfolder}/1_align/1.3_${aligner}_check_bmge" -name '*.ali' | wc -l)
ns_mafft_check_bmge=$(grep -c -h '>' "${runfolder}/1_align/1.3_${aligner}_check_bmge"/*.ali | awk '{sum=sum+$1}END{print sum}')
nt_mafft_check_bmge=$(grep -h '>' "${runfolder}/1_align/1.3_${aligner}_check_bmge"/*.ali | sort -u | wc -l)

## Count files and sequences in 1.4_mafft_check_bmge_treeshrink
nf_mafft_check_bmge_treeshrink=$(find "${runfolder}/1_align/1.4_${aligner}_check_bmge_treeshrink" -name '*.ali' | wc -l)
ns_mafft_check_bmge_treeshrink=$(grep -c -h '>' "${runfolder}/1_align/1.4_${aligner}_check_bmge_treeshrink"/*.ali | awk '{sum=sum+$1}END{print sum}')
nt_mafft_check_bmge_treeshrink=$(grep -h '>' "${runfolder}/1_align/1.4_${aligner}_check_bmge_treeshrink"/*.ali | sort -u | wc -l)

## Count taxa in astral tree
nt_astral=$(sed 's/[(,]/\n/g' "${runfolder}/2_trees/2.2_mafft_check_bmge_treeshrink_pargenes/astral_run/output_species_tree.newick" | grep -c .)

# Count taxa in input trees to astral
minntax=
maxntax=0
while read -r tree ; do
  ntax=$(echo "${tree}" | sed 's/[(,]/\n/g' | grep -c .)
  if [ "${minntax}" = '' ] ; then
      minntax="${ntax}"
      maxntax="${ntax}"
  fi
  if [ "${ntax}" -gt "${maxntax}" ] ; then
      maxntax="${ntax}"
  elif [ "${ntax}" -lt "${minntax}" ] ; then
      minntax="${ntax}"
  fi
done < "${runfolder}/2_trees/2.2_mafft_check_bmge_treeshrink_pargenes/astral_run/gene_trees.newick"


######################################################################################
## Step 12. Print README.md
## Input:
## Output: README.md
## TODO:

readme="${runfolder}/README.md"
outputfolder=$(basename ${runfolder})

cat << EOF > "${readme}"
# Summary 

## Workflow

Name: \`$(basename "$0")\`

Version: ${version}

Run completed: $(date "+%F %T")

## Input

\`${unaligned}\`

with ${nf_unaligned} fasta files (${datatype} format). Total of ${ns_unaligned} sequences from ${nt_unaligned} sequence names.

## Output

#### Run folder:

\`${runfolder}\`

#### Logfile:

[\`align-and-trees-parallel-workflow.log\`](align-and-trees-parallel-workflow.log)

#### The ASTRAL-species tree (${nt_astral} terminals):

[\`2_trees/2.2_mafft_check_bmge_treeshrink_pargenes/astral_run/output_species_tree.newick\`](2_trees/2.2_mafft_check_bmge_treeshrink_pargenes/astral_run/output_species_tree.newick)

#### Gene trees (min Ntax=${minntax}, max Ntax=${maxntax}):

[\`2_trees/2.2_mafft_check_bmge_treeshrink_pargenes/astral_run/mlsearch_run/results/*/*.raxml.bestTree\`](2_trees/2.2_mafft_check_bmge_treeshrink_pargenes/astral_run/mlsearch_run/results/)

#### Alignments:

1. [\`1_align/1.1_mafft/*.ali\`](1_align/1.1_mafft/)
2. [\`1_align/1.2_mafft_check/*.ali\`](1_align/1.2_mafft_check/)
3. [\`1_align/1.3_mafft_check_bmge/*.ali\`](1_align/1.3_mafft_check_bmge/)
4. [\`1_align/1.4_mafft_check_bmge_treeshrink/*.ali\`](1_align/1.4_mafft_check_bmge_treeshrink/)

## Filtering summary

| Step | Tool | Nfiles | Nseqs | Ntax |
| ---  | --- | --- | --- | --- |
| 1. | Unaligned | ${nf_unaligned} | ${ns_unaligned} | ${nt_unaligned} |
| 2. | Mafft | ${nf_mafft} | ${ns_mafft} | ${nt_mafft} |
| 3. | Check w. raxml | ${nf_mafft_check} | ${ns_mafft_check} | ${nt_mafft_check} |
| 4. | BMGE | ${nf_mafft_check_bmge} | ${ns_mafft_check_bmge} | ${nt_mafft_check_bmge} |
| 5. | TreeShrink | ${nf_mafft_check_bmge_treeshrink} | ${ns_mafft_check_bmge_treeshrink} | ${nt_mafft_check_bmge_treeshrink} |

EOF


######################################################################################
## End
echo -e "\n## ATPW [$(date "+%F %T")]: Reached end of the script\n" 2>&1 | tee -a "${logfile}"

exit 0

