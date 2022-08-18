#!/bin/bash -l

set -uo pipefail

# Default settings
version="0.7.3"
logfile=
modeltestcriterion="BIC"
datatype='nt'

nprocs=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null)
ncores="${nprocs}"        # TODO: Do we need to adjust?
modeltestperjobcores='4'  # TODO: Adjust? This value needs to be at least 4!
threadsforaligner='2'     # TODO: Adjust?
#threadsforrealigner='2'   # TODO: Adjust?

bmgejar="/home/nylander/src/BMGE-1.12/BMGE.jar"                # <<<<<<<<<< CHANGE HERE
pargenes="/home/nylander/src/ParGenes/pargenes/pargenes.py"    # <<<<<<<<<< CHANGE HERE
treeshrink="/home/nylander/src/TreeShrink/run_treeshrink.py"   # <<<<<<<<<< CHANGE HERE
macse="home/nylander/jb/johaberg-all/src/omm_macse_v10.02.sif" # <<<<<<<<<< CHANGE HERE

aligner="mafft" # Name of aligner, not path to binary
alignerbin="mafft"
alignerbinopts=" --auto --thread ${threadsforaligner} --quiet"
realigner="mafft" # Name of realigner, not path to binary
realignerbinopts="${alignerbinopts}"

#aligner="macse"
#alignerbin="/home/nylander/jb/johaberg-all/src/omm_macse_v10.02.sif"
#alignerbinopts=" -java_mem 2000m"

raxmlng="raxml-ng"
fastagap="fastagap.pl"
catfasta2phyml="catfasta2phyml.pl"
phylip2fasta="phylip2fasta.pl"


# Usage
function usage {
cat <<End_Of_Usage

$(basename "$0") version ${version}

What:
           Phylogenetics in parallel

By:
           Johan Nylander

Usage:
           $(basename "$0") -d nt|aa [options] infolder outfolder

Options:
           -d type   -- Specify data type: nt or aa. (Mandatory)
           -t number -- Specify the number of threads. Default: ${ncores}
           -m crit   -- Model test criterion: BIC, AIC or AICC. Default: ${modeltestcriterion}
           -A        -- Do not run initial alignment (assume aligned input). Default is to assume unaligned input.
           -B        -- Do not run BMGE. Default is to use BMGE.
           -v        -- Print version
           -h        -- Print help message

Examples:
           $(basename "$0") -d nt -t 8 data out

Input:
           Folder with fasta formatted sequence files (files need to have suffix ".fas").

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


# Check programs
prog_exists() {
    if [ ! -x "$(command -v "$1")" ] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! No executable file $1"
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
  "${realigner}" \
  "${pargenes}" \
  "${treeshrink}" ; do
  prog_exists "${p}"
done


# Model-selection criterion and default models
modelforraxmltest='GTR'
datatypeforbmge='DNA'
modelforpargenesfixed='GTR+G8+F'


# Arguments and defaults
doalign=1
dobmge=1
Aflag=
Bflag=
dflag=
tflag=
mflag=

while getopts 'ABd:t:m:vh' OPTION
do
  case $OPTION in
  A) Aflag=1
     doalign=
     ;;
  B) Bflag=1
     dobmge=
     ;;
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


# Check if positional args are folders and create log file
if [ $# -ne 2 ]; then
  echo 1>&2 "Usage: $0 [options] /path/to/folder/with/fas/files /path/to/output/folder"
  exit 1
else
  input=$(readlink -f "$1")
  runfolder=$(readlink -f "$2")
fi

if [ -d "${runfolder}" ]; then
  echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! folder ${runfolder} exists"
  exit 1
else
  mkdir -p "${runfolder}"
  mkdir -p "${runfolder}/1_align"
  mkdir -p "${runfolder}/2_trees"
  mkdir -p "${runfolder}/3_treeshrink"
  logfile="${runfolder}/ATPW.log"
  echo -e "\n## ATPW [$(date "+%F %T")]: Start" 2>&1 | tee "${logfile}"
  echo -e "\n## ATPW [$(date "+%F %T")]: Created output folder ${runfolder}" 2>&1 | tee "${logfile}"
fi

if [ -d "${input}" ] ; then
    nfas=$(find "${input}" -name '*.fas' | wc -l)
  if [ "${nfas}" -gt 1 ] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]: Found ${nfas} .fas files in folder ${input}" 2>&1 | tee "${logfile}"
  else
    echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! Could not find .fas files in folder ${input}" 2>&1 | tee "${logfile}"
      exit 1
  fi
else
  echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! Folder ${input} can not be found" 2>&1 | tee "${logfile}"
  exit 1
fi


## Check options
if [ ! "${dflag}" ] ; then
  echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! Need to supply data type ('nt' or 'aa') with '-d'" 2>&1 | tee "${logfile}"
  exit 1
elif [ "${dflag}" ] ; then
  lcdval=${dval,,} # to lowercase
  if [[ "${lcdval}" != @(nt|aa) ]] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! -d should be 'nt' or 'aa'" 2>&1 | tee "${logfile}"
    exit 1
  else
    datatype="${lcdval}"
  fi
fi
if [ "${datatype}" == 'aa' ] ; then
  datatypeforbmge='AA'
  modelforraxmltest='LG'
  modelforpargenesfixed='LG+G8+F'
fi

if [ "${Aflag}" ] ; then
  echo -e "\n## ATPW [$(date "+%F %T")]: Data is assumed to be aligned. Skipping first alignment step." 2>&1 | tee "${logfile}"
fi

if [ "${Bflag}" ] ; then
  echo -e "\n## ATPW [$(date "+%F %T")]: Skipping the BMGE step." 2>&1 | tee "${logfile}"
fi

if [ "${tflag}" ] ; then
  threads="${tval}"
  ncores="${threads}" # TODO: differentiate these variables
fi

if [ "${mflag}" ] ; then
  lcmval=${mval,,} # to lowercase
  if [[ "${lcdval}" != @(bic|aic|aicc) ]] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! -m should be 'bic', 'aic', or 'aicc'" 2>&1 | tee "${logfile}"
  else
    modeltestcriterion="${lcmval}"
  fi
fi


# Needed for some bash functions
# TODO: Double check which are needed
export runfolder
export phylip2fasta
export aligner
export realigner


# Functions
checkNtaxaInPhylip() {

  # Function for checking and removing phylip files with less than N taxa
  # If other max N, use, e.g., "parallel checkNtaxaInPhylip {} 10"

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


checkNtaxaInFasta() {

  # Function for checking and removing fasta files with less than N taxa
  # If other max N, use, e.g., "parallel checkNtaxaInFasta {} 10"

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


align() {

  # Alignments with mafft. Convert lower case mafft output to uppercase.
  # Input: inputfolder/*.fas
  # Output: 1_align/1.1_mafft/*.ali
  # Call: align "${input}" "${runfolder}/1_align/1.1_${aligner}"
  # TODO: use threads

  local inputfolder="$1"
  local outputfolder="$2"
  echo -e "\n## ATPW [$(date "+%F %T")]: Align with ${aligner}" 2>&1 | tee -a "${logfile}"
  mkdir -p "${outputfolder}"
  find "${inputfolder}" -type f -name '*.fas' | \
    parallel ''"${alignerbin}"' '"${alignerbinopts}"' {} | '"sed '/>/ ! s/[a-z]/\U&/g'"' > '"${outputfolder}"'/{/.}.'"${aligner}"'.ali' >> "${logfile}" 2>&1
}


runMacse() {

  # Run MACSE alignments 
  # Input: ${input}/*.fas
  # Output: 1_align/1.2_macse
  # Call: runMacse "${input}" "${runfolder}/1_align/1.2_macse"
  # Note: use ${aligner} instead of 'macse', and
  # ${alignerbinopts} instead of "--java_mem 2000m"
  # TODO: Figure out how to use together with collectMacse. Perhaps fuse?

  inputfolder="$1"

  runPara() {
      f="$1"
      g=$(basename "${f}" .fas)
      "${macse}" \
        --in_seq_file "${f}" \
        --out_dir "${g}" \
        --out_file_prefix "${g}" \
        --java_mem 2000m
      }
  find "${inputfolder}" -type f -name '*.fas' | \
    parallel runPara {} >> "${logfile}" 2>&1
}
export -f runMacse


collectMacse() {

  # Collect MACSE alignments into one file
  # Input: resulting folder from runMacse
  # Output: one alignment folder in "${runfolder}/1_align/1.2_macse"
  # Call: collectMacse inputfolder outputfolder
  # TODO: Figure out how to use together with runMacse. Perhaps fuse?

    #mkdir -p /home/nylander/jb/johaberg-all/run/aa-baits-macse-trees/ali
    #for f in $(find /home/nylander/jb/johaberg-all/data/mckenna-vasili-20-vasili-19-vasili-21-miller-ngi/AA/pmacse-translated-combined -name '*_final_align_AA.aln') ; do
    #  g=$(basename "${f}" _final_align_AA.aln)
    #  cp "${f}" /home/nylander/jb/johaberg-all/run/aa-baits-macse-trees/ali/"${g}".ali
    #done

  echo "Not implemented"

}
export -f collectMacse


checkAlignmentWithRaxml() {

  # Check alignments with raxml-ng
  # Input: 1_align/1.2_mafft_check/*.mafft.ali
  # Output: Folder 1_align/1.2_mafft_check/
  # Call: checkAlignmentWithRaxml "${runfolder}/1_align/1.1_${aligner}" "${runfolder}/1_align/1.2_${aligner}_check"
  # TODO:

  local inputfolder="$1"
  local outputfolder="$2"
  echo -e "\n## ATPW [$(date "+%F %T")]: Check alignments with raxml-ng" | tee -a "${logfile}"
  mkdir -p "${outputfolder}"
  ln -s -f "${inputfolder}"/*.ali "${outputfolder}"
  find -L "${outputfolder}" -type f -name '*.ali' | \
    parallel ''"${raxmlng}"' --check --msa {} --threads 1 --model '"${modelforraxmltest}"'' >> "${logfile}" 2>&1
  find "${outputfolder}" -type f -name '*.log' | \
    parallel 'if grep -q "^ERROR" {} ; then echo "## ATPW: Found error in {}"; rm -v {=s/\.raxml\.log//=} ; fi' >> "${logfile}" 2>&1
  rm "${outputfolder}"/*.log "${outputfolder}"/*.raxml.reduced.phy
}


runBmge() {

  # Run BMGE
  # Input: 1_align/1.2_mafft_check/*.mafft.ali (symlinks)
  # Output: 1_align/1.3_mafft_check_bmge/*.bmge.ali
  # Call: runBmge "${runfolder}/1_align/1.2_${aligner}_check/" "${runfolder}/1_align/1.3_mafft_check_bmge"
  # TODO:

  local inputfolder="$1"
  local outputfolder="$2"
  echo -e "\n## ATPW [$(date "+%F %T")]: Run BMGE" | tee -a "${logfile}"
  mkdir -p "${outputfolder}"
  cd "${outputfolder}" || exit
  find -L "${inputfolder}/" -type f -name '*.ali' | \
    parallel 'java -jar '"${bmgejar}"' -i {} -t '"${datatypeforbmge}"' -of {/.}.bmge.ali' >> "${logfile}" 2>&1
  cd .. || exit
}


checkNtaxa() {

  # Check and remove if any of the .suffix files have less than 4 taxa
  # Input: input/*.suffix
  # Output: remove input/*.suffix files
  # Call: checkNtaxaFas input 4 .suffix
  # TODO: Have this function create yet another folder? Use symlinks for files from inputfolder?

  local inputfolder="$1"
  local min="$2"
  local suffix="$3"
  echo -e "\n## ATPW [$(date "+%F %T")]: Check and remove if any files have less than 4 taxa" 2>&1 | tee -a "${logfile}"
  find "${inputfolder}" -type f -name "*${suffix}" | \
    parallel 'checkNtaxaInFasta {} '"${min}"'' >> "${logfile}" 2>&1
}


checkNtaxaOutputAli() {

  # Check and remove if any of the output.ali files have less than 4 taxa
  # Input: 1_align/1.3_mafft_check_bmge/*.mafft.bmge.ali
  # Output: remove /1_align/1.3_mafft_check_bmge/*.mafft.bmge.ali files
  # Call: checkNtaxaOutputAli 1_align/1.3_mafft_check_bmge/ 4
  # TODO: Use when we have other .ali files except the output.ali from treeshrink

  local inputfolder="$1"
  local min="$2"
  echo -e "\n## ATPW [$(date "+%F %T")]: Check and remove if any files have less than 4 taxa" 2>&1 | tee -a "${logfile}"
  find "${inputfolder}" -type f -name 'output.ali' | \
    parallel 'checkNtaxaInFasta {} '"${min}"''>> "${logfile}" 2>&1
}


pargenesFixedModel() {

  # Run pargenes with fixed model
  # Input: /1_align/1.3_mafft_check_bmge
  # Output: /2_trees/2.1_mafft_check_bmge_pargenes
  # Call: pargenesFixedModel "${runfolder}/1_align/1.3_mafft_check_bmge" "${runfolder}/2_trees/2.1_mafft_check_bmge_pargenes"
  # TODO: Create the "${runfolder}/2_trees" outside the function!

  local inputfolder="$1"
  local outputfolder="$2"
  echo -e "\n## ATPW [$(date "+%F %T")]: Run pargenes with fixed model" 2>&1 | tee -a "${logfile}"
  "${pargenes}" \
    --alignments-dir "${inputfolder}" \
    --output-dir "${outputfolder}" \
    --cores "${ncores}" \
    --datatype "${datatype}" \
    --raxml-global-parameters-string "--model ${modelforpargenesfixed}" >> "${logfile}" 2>&1
}


setupTreeshrink() {

 # Setup data for TreeShrink
 # Input: 3_treeshrink/3.1_treeshrink
 # Output: 3_treeshrink/3.1_treeshrink
 # Call: setupTreeshrink "${runfolder}/2_trees/2.1_mafft_check_bmge_pargenes/mlsearch_run/results" "${runfolder}/1_align/1.3_mafft_check_bmge" "${runfolder}/3_treeshrink/3.1_treeshrink"
 # TODO:
 inputfolderone="$1"     # where to look for trees
 inputfoldertwo="$2"     # where to look for alignments
 outputfolderthree="$3"  # output
 export inputfolderone
 export inputfoldertwo
 export outputfolderthree
 mkdir -p "${outputfolderthree}"

 copyAndConvert () {
   local f=
   f=$(basename "$1" .raxml.bestTree) # f=p3896_EOG7SFVKF_mafft_bmge_ali
   mkdir -p "${outputfolderthree}/${f}"
   ln -s "$1" "${outputfolderthree}/${f}/raxml.bestTree"
   sear="_${aligner}_bmge_ali"
   repl=".${aligner}.bmge.ali"
   local a=${f/$sear/$repl} # a=p3896_EOG7SFVKF.mafft.bmge.ali
   ln -s "${inputfoldertwo}/${a}" "${outputfolderthree}/${f}/alignment.ali"
 }
 export -f copyAndConvert

 find "${inputfolderone}" -type f -name '*.raxml.bestTree' | \
   parallel copyAndConvert {} >> "${logfile}" 2>&1
}


setupTreeshrinkNoAlignerNoBmge() {

 # Setup data for TreeShrink
 # Input: 3_treeshrink/3.1_treeshrink
 # Output: 3_treeshrink/3.1_treeshrink
 # Call: setupTreeshrinkNoAlignerNoBmge "${runfolder}/2_trees/2.1_pargenes/mlsearch_run/results" "${runfolder}/1_align/1.0_input" "${runfolder}/3_treeshrink/3.1_treeshrink"
 # TODO:
 inputfolderone="$1"     # where to look for trees
 inputfoldertwo="$2"     # where to look for alignments
 outputfolderthree="$3"  # output
 export inputfolderone
 export inputfoldertwo
 export outputfolderthree
 mkdir -p "${outputfolderthree}"

 copyAndConvertNoAlignerNoBmge () {
   local f=
   f=$(basename "$1" .raxml.bestTree) # f=p3896_EOG7SFVKF
   mkdir -p "${outputfolderthree}/${f}"
   ln -s "$1" "${outputfolderthree}/${f}/raxml.bestTree"
   local a=${f/_ali/\.ali} # a=p3896_EOG7SFVKF.ali
   ln -s "${inputfoldertwo}/${a}" "${outputfolderthree}/${f}/alignment.ali"
 }
 export -f copyAndConvertNoAlignerNoBmge

 find "${inputfolderone}" -type f -name '*.raxml.bestTree' | \
   parallel copyAndConvertNoAlignerNoBmge {} >> "${logfile}" 2>&1
}


setupTreeshrinkNoBmge() {

 # Setup data for TreeShrink
 # Input: 3_treeshrink/3.1_treeshrink
 # Output: 3_treeshrink/3.1_treeshrink
 # Call: setupTreeshrink "${runfolder}/2_trees/2.1_mafft_check_pargenes/mlsearch_run/results" "${runfolder}/1_align/1.3_mafft_check" "${runfolder}/3_treeshrink/3.1_treeshrink"
 # TODO:
 inputfolderone="$1"     # where to look for trees
 inputfoldertwo="$2"     # where to look for alignments
 outputfolderthree="$3"  # output
 export inputfolderone
 export inputfoldertwo
 export outputfolderthree
 mkdir -p "${outputfolderthree}"

 copyAndConvertNoBmge () {
   local f=
   f=$(basename "$1" .raxml.bestTree) # f=p3896_EOG7SFVKF_mafft_ali
   mkdir -p "${outputfolderthree}/${f}"
   ln -s "$1" "${outputfolderthree}/${f}/raxml.bestTree"
   sear="_${aligner}_ali"
   repl=".${aligner}.ali"
   local a=${f/$sear/$repl} # a=p3896_EOG7SFVKF.mafft.ali
   ln -s "${inputfoldertwo}/${a}" "${outputfolderthree}/${f}/alignment.ali"
 }
 export -f copyAndConvertNoBmge

 find "${inputfolderone}" -type f -name '*.raxml.bestTree' | \
   parallel copyAndConvertNoBmge {} >> "${logfile}" 2>&1
}


runTreeshrink() {

  # Run TreeShrink
  # Input: 3_treeshrink/3.1_treeshrink
  # Output: 3_treeshrink/3.1_treeshrink
  # Call: runTreeshrink  "${runfolder}/3_treeshrink/3.1_treeshrink"

  local inputfolder="$1"
  echo -e "\n## ATPW [$(date "+%F %T")]: Run treeshrink" 2>&1 | tee -a "${logfile}"
  "${treeshrink}" \
    --indir "${inputfolder}" \
    --tree 'raxml.bestTree' \
    --alignment "alignment.ali" >> "${logfile}" 2>&1
}


realignerOutputAli() {

  # Realign using realigner (search for "output.ali" files). Convert mafft output to upper case.
  # Input: 3_treeshrink/3.1_treeshrink/
  # Output: 1_align/1.4_mafft_check_bmge_treeshrink
  # Call: realignerOutputAli  "${runfolder}/3_treeshrink/3.1_treeshrink/" "${runfolder}/1_align/1.4_mafft_check_bmge_treeshrink"
  # TODO: Check if I can avoid the specific search for "output.ali" (there are other .ali files in in the input folder, but they are symlinks!)

  local inputfolder="$1"
  local outputfolder="$2"
  echo -e "\n## ATPW [$(date "+%F %T")]: Realign using ${realigner}" 2>&1 | tee -a "${logfile}"
  mkdir -p "${outputfolder}"
  find "${inputfolder}" -type f -name 'output.ali' | \
    parallel 'b=$(basename {//} .ali); '"${realigner}"' '"${realignerbinopts}"' <('"${fastagap}"' {}) | '"sed '/>/ ! s/[a-z]/\U&/g'"' > '"${outputfolder}"'/"${b//_/\.}"' >> "${logfile}" 2>&1
}


realignerAli() {

  # Realign using realigner (search for ".ali" files). Convert mafft output to upper case.
  # Input: 3_treeshrink/3.1_input-bmge/
  # Output: 1_align/1.4_mafft_check_bmge_treeshrink
  # Call: realignerOutputAli  "${runfolder}/3_treeshrink/3.1_treeshrink/" "${runfolder}/1_align/1.4_mafft_check_bmge_treeshrink"
  # TODO: Check if I can avoid the specific search for "output.ali" (there are other .ali files in in the input folder, but they are symlinks!)

  local inputfolder="$1"
  local outputfolder="$2"
  echo -e "\n## ATPW [$(date "+%F %T")]: Realign using ${realigner}" 2>&1 | tee -a "${logfile}"
  mkdir -p "${outputfolder}"
  find "${inputfolder}" -type f -name '*.ali' | \
    parallel 'b=$(basename {//} .ali); '"${realigner}"' '"${realignerbinopts}"' <('"${fastagap}"' {}) | sed '/>/ ! s/[a-z]/\U&/g' > '"${outputfolder}"'/"${b//_/\.}"' >> "${logfile}" 2>&1
}


pargenesModeltestAstral() {

  # Run pargenes with modeltest, finish with ASTRAL
  # Input: /1_align/1.3_mafft_check_bmge
  # Output: /2_trees/2.1_mafft_check_bmge_pargenes
  # Call: pargenesModeltestAstral "${runfolder}/1_align/1.4_mafft_check_bmge_treeshrink" "${runfolder}/2_trees/2.2_mafft_check_bmge_treeshrink_pargenes"
  # TODO:

  local inputfolder="$1"
  local outputfolder="$2"
  echo -e "\n## ATPW [$(date "+%F %T")]: Run pargenes with model selection, finish with ASTRAL" 2>&1 | tee -a "${logfile}"
  "${pargenes}" \
    --alignments-dir "${inputfolder}" \
    --output-dir "${outputfolder}" \
    --cores "${ncores}" \
    --datatype "${datatype}" \
    --use-modeltest \
    --modeltest-criteria "${modeltestcriterion}" \
    --modeltest-perjob-cores "${modeltestperjobcores}" \
    --use-astral >> "${logfile}" 2>&1
}


count() {

  # Count genes and sequences after each step
  # Input:
  # Output:
  # Call: count
  # TODO: Rewrite to avoid hard codes parts
  
  nf_mafft='NA'
  ns_mafft='NA'
  nt_mafft='NA'
  nf_mafft_check='NA'
  ns_mafft_check='NA'
  nt_mafft_check='NA'
  nf_mafft_check_bmge='NA'
  ns_mafft_check_bmge='NA'
  nt_mafft_check_bmge='NA'
  nf_mafft_check_bmge_treeshrink='NA'
  ns_mafft_check_bmge_treeshrink='NA'
  nt_mafft_check_bmge_treeshrink='NA'
  nf_0_input='NA'
  ns_0_input='NA'
  nt_0_input='NA'


  # Count files and sequences in input
  nf_input=$(find "${input}" -name '*.fas' | wc -l)
  ns_input=$(grep -c -h '>' "${input}"/*.fas | awk '{sum=sum+$1}END{print sum}')
  nt_input=$(grep -h '>' "${input}"/*.fas | sort -u | wc -l)

  if [ "${doalign}" ] ; then
    # Count files and sequences in 1.1_mafft
    if [ -d "${runfolder}/1_align/1.1_${aligner}" ] ; then
      nf_mafft=$(find  "${runfolder}/1_align/1.1_${aligner}" -name '*.ali' | wc -l)
      ns_mafft=$(grep -c -h '>' "${runfolder}/1_align/1.1_${aligner}"/*.ali | awk '{sum=sum+$1}END{print sum}')
      nt_mafft=$(grep -h '>' "${runfolder}/1_align/1.1_${aligner}"/*.ali | sort -u | wc -l)
    fi
    # Count files and sequences in 1.2_mafft_check
    if [ -d "${runfolder}/1_align/1.2_${aligner}_check" ] ; then
      nf_mafft_check=$(find -L "${runfolder}/1_align/1.2_${aligner}_check" -name '*.ali' | wc -l)
      ns_mafft_check=$(grep -c -h '>' "${runfolder}/1_align/1.2_${aligner}_check"/*.ali | awk '{sum=sum+$1}END{print sum}')
      nt_mafft_check=$(grep -h '>' "${runfolder}/1_align/1.2_${aligner}_check"/*.ali | sort -u | wc -l)
    fi
    if [ "${dobmge}" ] ; then
      # Count files and sequences in 1.3_mafft_check_bmge
      if [ -d "${runfolder}/1_align/1.3_${aligner}_check_bmge" ] ; then
        nf_mafft_check_bmge=$(find "${runfolder}/1_align/1.3_${aligner}_check_bmge" -name '*.ali' | wc -l)
        ns_mafft_check_bmge=$(grep -c -h '>' "${runfolder}/1_align/1.3_${aligner}_check_bmge"/*.ali | awk '{sum=sum+$1}END{print sum}')
        nt_mafft_check_bmge=$(grep -h '>' "${runfolder}/1_align/1.3_${aligner}_check_bmge"/*.ali | sort -u | wc -l)
      fi
      if [ -d "${runfolder}/1_align/1.4_${aligner}_check_bmge_treeshrink" ] ; then
        # Count files and sequences in 1.4_mafft_check_bmge_treeshrink
        nf_mafft_check_bmge_treeshrink=$(find "${runfolder}/1_align/1.4_${aligner}_check_bmge_treeshrink" -name '*.ali' | wc -l)
        ns_mafft_check_bmge_treeshrink=$(grep -c -h '>' "${runfolder}/1_align/1.4_${aligner}_check_bmge_treeshrink"/*.ali | awk '{sum=sum+$1}END{print sum}')
        nt_mafft_check_bmge_treeshrink=$(grep -h '>' "${runfolder}/1_align/1.4_${aligner}_check_bmge_treeshrink"/*.ali | sort -u | wc -l)
      fi
    fi
  else
    if [ -d "${runfolder}/1_align/1.0_input" ] ; then
      # Count files and sequences in 1.0_input
      nf_0_input=$(find  "${runfolder}/1_align/1.0_input" -name '*.ali' | wc -l)
      ns_0_input=$(grep -c -h '>' "${runfolder}/1_align/1.0_input"/*.ali | awk '{sum=sum+$1}END{print sum}')
      nt_0_input=$(grep -h '>' "${runfolder}/1_align/1.0_input"/*.ali | sort -u | wc -l)
    fi


  fi

 







  # Count taxa in astral tree
  astraltree=$(find "${runfolder}" -name 'output_species_tree.newick')
  nt_astral=$(sed 's/[(,]/\n/g' "${astraltree}"  | grep -c .)

  # Count taxa in input trees to astral
  astraltrees=$(find "${runfolder}" -name 'gene_trees.newick')
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
  done < "${astraltrees}"
}


createReadme() {

# Print README.md
# Input:
# Output: README.md
# Call: createReadme
# TODO: Not all folders are present if we run with -A and/or -B

readme="${runfolder}/README.md"
outputfolder=$(basename "${runfolder}")

cat << EOF > "${readme}"
# Summary 

## Workflow

Name: \`$(basename "$0")\`

Version: ${version}

Run completed: $(date "+%F %T")

## Input

\`${input}\`

with ${nf_input} fasta files (${datatype} format). Total of ${ns_input} sequences from ${nt_input} sequence names.

## Output

#### Run folder:

\`${runfolder}\`

#### Logfile:

[\`ATPW.log\`](ATPW.log)

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
| 1. | Input | ${nf_input} | ${ns_input} | ${nt_input} |
| 2. | Mafft | ${nf_mafft} | ${ns_mafft} | ${nt_mafft} |
| 3. | Check w. raxml | ${nf_mafft_check} | ${ns_mafft_check} | ${nt_mafft_check} |
| 4. | BMGE | ${nf_mafft_check_bmge} | ${ns_mafft_check_bmge} | ${nt_mafft_check_bmge} |
| 5. | TreeShrink | ${nf_mafft_check_bmge_treeshrink} | ${ns_mafft_check_bmge_treeshrink} | ${nt_mafft_check_bmge_treeshrink} |

EOF

}

# MAIN

# $input is either aligned or unaligned.
# if aligned, we can run BMGE or not
# We then want to run:
#     pargenes fixed
#     treeshrink
#     realign
#     pargenes modelselection+ASTRAL

# TODO: rewrite to avoid all hard coded paths

# Align or not, and check files with raxml
if [ "${doalign}" ] ; then
  checkNtaxa "${input}" 4 .fas
  align "${input}" "${runfolder}/1_align/1.1_${aligner}"
  checkAlignmentWithRaxml "${runfolder}/1_align/1.1_${aligner}" "${runfolder}/1_align/1.2_${aligner}_check"
else
  mkdir -p "${runfolder}/1_align/1.0_input"
  find "${input}" -name '*.fas' | \
      parallel cp -s {} "${runfolder}/1_align/1.0_input/{/.}.ali"
  checkNtaxa "${runfolder}/1_align/1.0_input" 4 .ali
  checkAlignmentWithRaxml "${runfolder}/1_align/1.0_input" "${runfolder}/1_align/1.0_input_check"
fi

# bmge or not
if [ "${dobmge}" ] ; then
  if [ "${doalign}" ] ; then
    runBmge "${runfolder}/1_align/1.2_${aligner}_check/" "${runfolder}/1_align/1.3_${aligner}_check_bmge"
    checkNtaxa "${runfolder}/1_align/1.3_${aligner}_check_bmge" 4 .ali
  else
    runBmge "${runfolder}/1_align/1.0_input_check" "${runfolder}/1_align/1.3_input_check_bmge"
    checkNtaxa "${runfolder}/1_align/1.3_input_check_bmge" 4 .ali
  fi
fi

# pargenes, fixed model
if [ "${doalign}" ] ; then
  if [ "${dobmge}" ] ; then
    pargenesFixedModel "${runfolder}/1_align/1.3_${aligner}_check_bmge" "${runfolder}/2_trees/2.1_${aligner}_check_bmge_pargenes"
  else
    pargenesFixedModel "${runfolder}/1_align/1.3_${aligner}_check" "${runfolder}/2_trees/2.1_${aligner}_check_pargenes"
  fi
else
  pargenesFixedModel "${runfolder}/1_align/1.0_input_check" "${runfolder}/2_trees/2.1_input_check_pargenes"
fi

# setup for treeshrink
if [ "${doalign}" ] ; then
  if [ "${dobmge}" ] ; then
    setupTreeshrink "${runfolder}/2_trees/2.1_${aligner}_check_bmge_pargenes/mlsearch_run/results" "${runfolder}/1_align/1.3_${aligner}_check_bmge" "${runfolder}/3_treeshrink/3.1_treeshrink"
  else
    setupTreeshrinkNoBmge "${runfolder}/2_trees/2.1_${aligner}_check_pargenes/mlsearch_run/results" "${runfolder}/1_align/1.3_${aligner}_check" "${runfolder}/3_treeshrink/3.1_treeshrink"
  fi
else
  setupTreeshrinkNoAlignerNoBmge "${runfolder}/2_trees/2.1_input_check_pargenes/mlsearch_run/results" "${runfolder}/1_align/1.0_input_check" "${runfolder}/3_treeshrink/3.1_treeshrink"
fi

runTreeshrink "${runfolder}/3_treeshrink/3.1_treeshrink"

checkNtaxaOutputAli "${runfolder}/3_treeshrink/3.1_treeshrink" 4

if [ "${doalign}" ] ; then
  if [ "${dobmge}" ] ; then
    realignerOutputAli "${runfolder}/3_treeshrink/3.1_treeshrink/" "${runfolder}/1_align/1.4_${aligner}_check_bmge_treeshrink"
  else
    realignerOutputAli "${runfolder}/3_treeshrink/3.1_treeshrink/" "${runfolder}/1_align/1.4_${aligner}_check_treeshrink"
  fi
else
  realignerOutputAli "${runfolder}/3_treeshrink/3.1_treeshrink/" "${runfolder}/1_align/1.4_input_check_treeshrink"
fi

if [ "${doalign}" ] ; then
  if [ "${dobmge}" ] ; then
    pargenesModeltestAstral "${runfolder}/1_align/1.4_${aligner}_check_bmge_treeshrink" "${runfolder}/2_trees/2.2_${aligner}_check_bmge_treeshrink_pargenes"
  else
    pargenesModeltestAstral "${runfolder}/1_align/1.4_${aligner}_check_treeshrink" "${runfolder}/2_trees/2.2_${aligner}_check_treeshrink_pargenes"
  fi
else
  pargenesModeltestAstral "${runfolder}/1_align/1.4_input_check_treeshrink" "${runfolder}/2_trees/2.2_input_check_treeshrink_pargenes"
fi

#count

#createReadme

# End
echo -e "\n## ATPW [$(date "+%F %T")]: Reached end of the script\n" 2>&1 | tee -a "${logfile}"

exit 0

