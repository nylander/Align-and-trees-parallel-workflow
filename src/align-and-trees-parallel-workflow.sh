#!/bin/bash -l

set -uo pipefail
# TODO: put back -e

# Default settings
version="0.7.6"
logfile=
modeltestcriterion="BIC"
datatype='nt'
mintaxfilter=4

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
cat << End_Of_Usage

$(basename "$0") version ${version}

What:
           Phylogenetics in parallel

           Performs the following steps:
           1. Do multiple sequence alignment (optional)
           2. Filter using BMGE (optional)
           3. Filter using TreeShrink (optional)
           4. Estimate gene trees with raxml-ng using
              automatic model selection
           5. Estimate species tree using ASTRAL

By:
           Johan Nylander

Usage:
           $(basename "$0") -d nt|aa [options] infolder outfolder

Options:
           -d type   -- Specify data type: nt or aa. (Mandatory)
           -n number -- Specify the number of threads. Default: ${ncores}
           -m crit   -- Model test criterion: BIC, AIC or AICC. Default: ${modeltestcriterion}
           -f number -- Minimum number of taxa when filtering alignments. Default: ${mintaxfilter}
           -A        -- Do not run mafft (assume aligned input)
           -B        -- Do not run BMGE
           -T        -- Do not run TreeShrink
           -v        -- Print version
           -h        -- Print help message

Examples:
           $(basename "$0") -d nt -t 8 data out

Input:
           Folder with fasta formatted sequence files.
           Files need to have suffix ".fas"!

Output:
           Folders with filtered alignments and species-
           and gene-trees.
           Summary README.md file.
           Log file ATPW.log.

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
dotreeshrink=1
Aflag=
Bflag=
Tflag=
dflag=
fflag=
mflag=
nflag=

while getopts 'ABTd:f:n:m:vh' OPTION
do
  case $OPTION in
  A) Aflag=1
     doalign=
     ;;
  B) Bflag=1
     dobmge=
     ;;
  T) Tflag=1
     dotreeshrink=
     ;;
  d) dflag=1
     dval="$OPTARG"
     ;;
  f) fflag=1
     fval="$OPTARG"
     ;;
  n) nflag=1
     nval="$OPTARG"
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
  logfile="${runfolder}/ATPW.log"
  echo -e "\n## ATPW [$(date "+%F %T")]: Start" 2>&1 | tee "${logfile}"
  echo -e "\n## ATPW [$(date "+%F %T")]: Created output folder ${runfolder}" 2>&1 | tee "${logfile}"
  echo -e "\n## ATPW [$(date "+%F %T")]: Created logfile ${logfile}" 2>&1 | tee "${logfile}"
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

if [ "${Tflag}" ] ; then
  echo -e "\n## ATPW [$(date "+%F %T")]: Skipping the TreeShrink step." 2>&1 | tee "${logfile}"
  echo -e "\n## ATPW [$(date "+%F %T")]: The -T flag is currently not implemented. Quitting"
  exit
fi

if [ "${nflag}" ] ; then
  nthreads="${nval}"
  ncores="${nthreads}" # TODO: differentiate these variables
fi

if [ "${mflag}" ] ; then
  lcmval=${mval,,} # to lowercase
  if [[ "${lcdval}" != @(bic|aic|aicc) ]] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! -m should be 'bic', 'aic', or 'aicc'" 2>&1 | tee "${logfile}"
  else
    modeltestcriterion="${lcmval}"
  fi
fi

if [ "${fflag}" ] ; then
  mintaxfilter="${fval}"
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
  echo -e "\n## ATPW [$(date "+%F %T")]: Check and remove if any files have less than ${mintaxfilter} taxa" 2>&1 | tee -a "${logfile}"
  find "${inputfolder}" -type f -name "*${suffix}" | \
    parallel 'checkNtaxaInFasta {} '"${min}"'' >> "${logfile}" 2>&1
  if [ ! "$(find ${inputfolder} -maxdepth 1 -type f -name "*${suffix}")" ] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]: WARNING! No ${suffix} files left in ${inputfolder}. Quitting." | tee -a "${logfile}"
    exit 1
  fi

}


checkNtaxaOutputAli() {

  # Check and remove if any of the output.ali files have less than 4 taxa
  # Input: 1_align/1.3_mafft_check_bmge/*.mafft.bmge.ali
  # Output: remove /1_align/1.3_mafft_check_bmge/*.mafft.bmge.ali files
  # Call: checkNtaxaOutputAli 1_align/1.3_mafft_check_bmge/ 4
  # TODO: Use when we have other .ali files except the output.ali from treeshrink

  local inputfolder="$1"
  local min="$2"
  echo -e "\n## ATPW [$(date "+%F %T")]: Check and remove if any files have less than ${mintaxfilter} taxa" 2>&1 | tee -a "${logfile}"
  find "${inputfolder}" -type f -name 'output.ali' | \
    parallel 'checkNtaxaInFasta {} '"${min}"''>> "${logfile}" 2>&1
  if [ ! "$(find ${inputfolder} -maxdepth 1 -type f -name 'output.ali')" ]; then
    echo -e "\n## ATPW [$(date "+%F %T")]: WARNING! No output.ali files left in ${inputfolder}. Quitting." | tee -a "${logfile}"
    exit 1
  fi

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

setupTreeshrinkBmgeNoAligner () {

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

 copyAndConvertBmgeNoAligner () {
   local f=
   f=$(basename "$1" .raxml.bestTree) # f=p3896_EOG7SFVKF_bmge_ali
   mkdir -p "${outputfolderthree}/${f}"
   ln -s "$1" "${outputfolderthree}/${f}/raxml.bestTree"
   sear="_bmge_ali"
   repl=".bmge.ali"
   local a=${f/$sear/$repl} # a=p3896_EOG7SFVKF.bmge.ali
   ln -s "${inputfoldertwo}/${a}" "${outputfolderthree}/${f}/alignment.ali"
 }
 export -f copyAndConvertBmgeNoAligner

 find "${inputfolderone}" -type f -name '*.raxml.bestTree' | \
   parallel copyAndConvertBmgeNoAligner {} >> "${logfile}" 2>&1
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

  nf_raw_input='NA'
  ns_raw_input='NA'
  nt_raw_input='NA'
  nf_aligner='NA'
  ns_aligner='NA'
  nt_aligner='NA'
  nf_aligner_check='NA'
  ns_aligner_check='NA'
  nt_aligner_check='NA'
  nf_aligner_check_bmge='NA'
  ns_aligner_check_bmge='NA'
  nt_aligner_check_bmge='NA'
  nf_aligner_check_bmge_treeshrink='NA'
  ns_aligner_check_bmge_treeshrink='NA'
  nt_aligner_check_bmge_treeshrink='NA'
  nf_aligner_check_treeshrink='NA'
  ns_aligner_check_treeshrink='NA'
  nt_aligner_check_treeshrink='NA'
  nf_input='NA'
  ns_input='NA'
  nt_input='NA'
  nf_input_check='NA'
  ns_input_check='NA'
  nt_input_check='NA'
  nf_input_check_bmge='NA'
  ns_input_check_bmge='NA'
  nt_input_check_bmge='NA'
  nf_input_check_bmge_treeshrink='NA'
  ns_input_check_bmge_treeshrink='NA'
  nt_input_check_bmge_treeshrink='NA'
  nf_input_check_treeshrink='NA'
  ns_input_check_treeshrink='NA'
  nt_input_check_treeshrink='NA'

  # Count files and sequences in raw input
  nf_raw_input=$(find "${input}" -name '*.fas' | wc -l)
  ns_raw_input=$(grep -c -h '>' "${input}"/*.fas | awk '{sum=sum+$1}END{print sum}')
  nt_raw_input=$(grep -h '>' "${input}"/*.fas | sort -u | wc -l)

  # Go through any potential output folders
  # 1.1_mafft
  if [ -d "${runfolder}/1_align/1.1_${aligner}" ] ; then
    nf_aligner=$(find "${runfolder}/1_align/1.1_${aligner}" -name '*.ali' | wc -l)
    ns_aligner=$(grep -c -h '>' "${runfolder}/1_align/1.1_${aligner}"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_aligner=$(grep -h '>' "${runfolder}/1_align/1.1_${aligner}"/*.ali | sort -u | wc -l)
  fi

  # 1.2_mafft_check
  if [ -d "${runfolder}/1_align/1.2_${aligner}_check" ] ; then
    nf_aligner_check=$(find -L "${runfolder}/1_align/1.2_${aligner}_check" -name '*.ali' | wc -l)
    ns_aligner_check=$(grep -c -h '>' "${runfolder}/1_align/1.2_${aligner}_check"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_aligner_check=$(grep -h '>' "${runfolder}/1_align/1.2_${aligner}_check"/*.ali | sort -u | wc -l)
  fi

  # 1.3_mafft_check_bmge
  if [ -d "${runfolder}/1_align/1.3_${aligner}_check_bmge" ] ; then
    nf_aligner_check_bmge=$(find "${runfolder}/1_align/1.3_${aligner}_check_bmge" -name '*.ali' | wc -l)
    ns_aligner_check_bmge=$(grep -c -h '>' "${runfolder}/1_align/1.3_${aligner}_check_bmge"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_aligner_check_bmge=$(grep -h '>' "${runfolder}/1_align/1.3_${aligner}_check_bmge"/*.ali | sort -u | wc -l)
  fi

  # 1.4_mafft_check_bmge_treeshrink
  if [ -d "${runfolder}/1_align/1.4_${aligner}_check_bmge_treeshrink" ] ; then
    nf_aligner_check_bmge_treeshrink=$(find "${runfolder}/1_align/1.4_${aligner}_check_bmge_treeshrink" -name '*.ali' | wc -l)
    ns_aligner_check_bmge_treeshrink=$(grep -c -h '>' "${runfolder}/1_align/1.4_${aligner}_check_bmge_treeshrink"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_aligner_check_bmge_treeshrink=$(grep -h '>' "${runfolder}/1_align/1.4_${aligner}_check_bmge_treeshrink"/*.ali | sort -u | wc -l)
  fi

  # 1.4_mafft_check_treeshrink
  if [ -d "${runfolder}/1_align/1.4_${aligner}_check_treeshrink" ] ; then
    nf_aligner_check_treeshrink=$(find "${runfolder}/1_align/1.4_${aligner}_check_treeshrink" -name '*.ali' | wc -l)
    ns_aligner_check_treeshrink=$(grep -c -h '>' "${runfolder}/1_align/1.4_${aligner}_check_treeshrink"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_aligner_check_treeshrink=$(grep -h '>' "${runfolder}/1_align/1.4_${aligner}_check_treeshrink"/*.ali | sort -u | wc -l)
  fi

  # 1.1_input
  if [ -d "${runfolder}/1_align/1.1_input" ] ; then
    nf_input=$(find "${runfolder}/1_align/1.1_input" -name '*.ali' | wc -l)
    ns_input=$(grep -c -h '>' "${runfolder}/1_align/1.1_input"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_input=$(grep -h '>' "${runfolder}/1_align/1.1_input"/*.ali | sort -u | wc -l)
  fi

  # 1.2_input_check
  if [ -d "${runfolder}/1_align/1.2_input_check" ] ; then
    nf_input_check=$(find -L "${runfolder}/1_align/1.2_input_check" -name '*.ali' | wc -l)
    ns_input_check=$(grep -c -h '>' "${runfolder}/1_align/1.2_input_check"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_input_check=$(grep -h '>' "${runfolder}/1_align/1.2_input_check"/*.ali | sort -u | wc -l)
  fi

  # 1.3_input_check_bmge
  if [ -d "${runfolder}/1_align/1.3_input_check_bmge" ] ; then
    nf_input_check_bmge=$(find "${runfolder}/1_align/1.3_input_check_bmge" -name '*.ali' | wc -l)
    ns_input_check_bmge=$(grep -c -h '>' "${runfolder}/1_align/1.3_input_check_bmge"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_input_check_bmge=$(grep -h '>' "${runfolder}/1_align/1.3_input_check_bmge"/*.ali | sort -u | wc -l)
  fi

  # 1.4_input_check_bmge_treeshrink
  if [ -d "${runfolder}/1_align/1.4_input_check_bmge_treeshrink" ] ; then
    nf_input_check_bmge_treeshrink=$(find "${runfolder}/1_align/1.4_input_check_bmge_treeshrink" -name '*.ali' | wc -l)
    ns_input_check_bmge_treeshrink=$(grep -c -h '>' "${runfolder}/1_align/1.4_input_check_bmge_treeshrink"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_input_check_bmge_treeshrink=$(grep -h '>' "${runfolder}/1_align/1.4_input_check_bmge_treeshrink"/*.ali | sort -u | wc -l)
  fi

  # 1.4_input_check_treeshrink
  if [ -d "${runfolder}/1_align/1.4_input_check_treeshrink" ] ; then
    nf_input_check_treeshrink=$(find "${runfolder}/1_align/1.4_input_check_treeshrink" -name '*.ali' | wc -l)
    ns_input_check_treeshrink=$(grep -c -h '>' "${runfolder}/1_align/1.4_input_check_treeshrink"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_input_check_treeshrink=$(grep -h '>' "${runfolder}/1_align/1.4_input_check_treeshrink"/*.ali | sort -u | wc -l)
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
  # TODO: rewrite to avoid hardcoding

  readme="${runfolder}/README.md"
  outputfolder=$(basename "${runfolder}")

  # Find locations of output
  astral_tree_path=$(find "${runfolder}" -type f -name 'output_species_tree.newick')
  gene_trees_path=$(find "${runfolder}" -type f -name 'gene_trees.newick')
  logfile_path=$(find "${runfolder}" -type f -name 'ATPW.log')

  if [ "${doalign}" ] ; then
    aligner_folder_path=$(find "${runfolder}" -type d -name "1.1_${aligner}")
    aligner_check_folder_path=$(find "${runfolder}" -type d -name "1.2_${aligner}_check")
    if [ "${dobmge}" ] ; then
      aligner_check_bmge_folder_path=$(find "${runfolder}" -type d -name "1.3_${aligner}_check_bmge")
      if [ "${dotreeshrink}" ] ; then
        aligner_check_bmge_threeshrink_folder_path=$(find "${runfolder}" -type d -name "1.4_${aligner}_check_bmge_treeshrink")
        steps='mafft, bmge, treeshrink, raxml-ng, astral'
      else
        steps='mafft, bmge, raxml-ng, astral'
      fi
    else
      if [ "${dotreeshrink}" ] ; then
        aligner_check_threeshrink_folder_path=$(find "${runfolder}" -type d -name "1.4_${aligner}_check_treeshrink")
        steps='mafft, treeshrink, raxml-ng, astral'
      fi
    fi
  else
    input_folder_path=$(find "${runfolder}" -type d -name '1.1_input')
    input_check_folder_path=$(find "${runfolder}" -type d -name '1.2_input_check')
    if [ "${dobmge}" ] ; then
      input_check_bmge_folder_path=$(find "${runfolder}" -type d -name '1.3_input_check_bmge')
      if [ "${dotreeshrink}" ] ; then
        input_check_bmge_threeshrink_folder_path=$(find "${runfolder}" -type d -name '1.4_input_check_bmge_treeshrink')
        steps='bmge, treeshrink, raxml-ng, astral'
      else
        steps='bmge, raxml-ng, astral'
      fi
    else
      if [ "${dotreeshrink}" ] ; then
        input_check_threeshrink_folder_path=$(find "${runfolder}" -type d -name '1.4_input_check_treeshrink')
        steps='treeshrink, raxml-ng, astral'
      fi
    fi
  fi

  cat <<- EOF > "${readme}"
# Align and Trees in Parallel - Summary

## Workflow

- Name: \`$(basename "$0")\`
- Version: ${version}
- Run completed: $(date "+%F %T")
- Steps: ${steps}

## Input data

\`${input}\`, with ${nf_raw_input} fasta files (${datatype} format).

Total of ${ns_raw_input} sequences from ${nt_raw_input} sequence names.

## Output

#### Run folder:

\`${runfolder}\`

#### Logfile:

[\`ATPW.log\`](${logfile_path#$runfolder/})

#### The ASTRAL-species tree (${nt_astral} terminals):

[\`output_species_tree.newick\`](${astral_tree_path#$runfolder/})

#### Gene trees (min Ntax=${minntax}, max Ntax=${maxntax}):

[\`gene_trees.newick\`](${gene_trees_path#$runfolder/})

#### Alignments:

EOF

  if [ "${doalign}" ] ; then
    echo -e "1. [\`1_align/1.1_"${aligner}"/*.ali\`](${aligner_folder_path#$runfolder/})" >> "${readme}"
    echo -e "2. [\`1_align/1.2_"${aligner}"_check/*.ali\`](${aligner_check_folder_path#$runfolder/})" >> "${readme}"
    if [ "${dobmge}" ] ; then
      echo -e "3. [\`1_align/1.3_"${aligner}"_check_bmge/*.ali\`](${aligner_check_bmge_folder_path#$runfolder/})" >> "${readme}"
      if [ "${dotreeshrink}" ] ; then
        echo -e "4. [\`1_align/1.4_"${aligner}"_check_bmge_treeshrink/*.ali\`]("${aligner_check_bmge_threeshrink_folder_path#$runfolder/}")" >> "${readme}"
      fi
    else
      if [ "${dotreeshrink}" ] ; then
        echo -e "4. [\`1_align/1.4_"${aligner}"_check_treeshrink/*.ali\`]("${aligner_check_threeshrink_folder_path#$runfolder/}")" >> "${readme}"
      fi
    fi
  else
    echo -e "1. [\`1_align/1.1_input/*.ali\`]("${input_folder_path#$runfolder/}")" >> "${readme}"
    echo -e "2. [\`1_align/1.2_input_check/*.ali\`]("${input_check_folder_path#$runfolder/}")" >> "${readme}"
    if [ "${dobmge}" ] ; then
      echo -e "3. [\`1_align/1.3_input_check_bmge/*.ali\`]("${input_check_bmge_folder_path#$runfolder/}")" >> "${readme}"
      if [ "${dotreeshrink}" ] ; then
        echo -e "4. [\`1_align/1.4_input_check_bmge_treeshrink/*.ali\`]("${input_check_bmge_threeshrink_folder_path#$runfolder/}")" >> "${readme}"
      fi
    else
      if [ "${dotreeshrink}" ] ; then
        echo -e "4. [\`1_align/1.4_input_check_treeshrink/*.ali\`]("${input_check_threeshrink_folder_path#$runfolder/}")" >> "${readme}"
      fi
    fi
  fi

  echo "" >> "${readme}"
  echo -e "## Filtering summary" >> "${readme}"
  echo "" >> "${readme}"
  echo -e "| Step | Tool | Nfiles | Nseqs | Ntax |" >> "${readme}"
  echo -e "| ---  | --- | --- | --- | --- |" >> "${readme}"
  echo -e "| 0. | Raw input | ${nf_raw_input} | ${ns_raw_input} | ${nt_raw_input} |" >> "${readme}"

  if [ "${doalign}" ] ; then
    echo -e "| 1. | "${aligner}" | ${nf_aligner} | ${ns_aligner} | ${nt_aligner} |" >> "${readme}"
    echo -e "| 2. | Check w. RAxML | ${nf_aligner_check} | ${ns_aligner_check} | ${nt_aligner_check} |" >> "${readme}"
    if [ "${dobmge}" ] ; then
      echo -e "| 3. | BMGE | ${nf_aligner_check_bmge} | ${ns_aligner_check_bmge} | ${nt_aligner_check_bmge} |" >> "${readme}"
      if [ "${dotreeshrink}" ] ; then
        echo -e "| 4. | TreeShrink | ${nf_aligner_check_bmge_treeshrink} | ${ns_aligner_check_bmge_treeshrink} | ${nt_aligner_check_bmge_treeshrink} |" >> "${readme}"
      fi
    else
      if [ "${dotreeshrink}" ] ; then
        echo -e "| 4. | TreeShrink | ${nf_aligner_check_treeshrink} | ${ns_aligner_check_treeshrink} | ${nt_aligner_check_treeshrink} |" >> "${readme}"
      fi
    fi
  else
    echo -e "| 1. | Input | ${nf_input} | ${ns_input} | ${nt_input} |" >> "${readme}"
    echo -e "| 2. | Check w. RAxML | ${nf_input_check} | ${ns_input_check} | ${nt_input_check} |" >> "${readme}"
    if [ "${dobmge}" ] ; then
      echo -e "| 3. | BMGE | ${nf_input_check_bmge} | ${ns_input_check_bmge} | ${nt_input_check_bmge} |" >> "${readme}"
      if [ "${dotreeshrink}" ] ; then
        echo -e "| 4. | TreeShrink | ${nf_input_check_bmge_treeshrink} | ${ns_input_check_bmge_treeshrink} | ${nt_input_check_bmge_treeshrink} |" >> "${readme}"
      fi
    else
      if [ "${dotreeshrink}" ] ; then
        echo -e "| 4. | TreeShrink | ${nf_input_check_treeshrink} | ${ns_input_check_treeshrink} | ${nt_input_check_treeshrink} |" >> "${readme}"
      fi
    fi
  fi
}

##################################################
# MAIN
##################################################

# TODO: rewrite to avoid all hard coded paths

# Align or not, and check files with raxml
if [ "${doalign}" ] ; then
  align "${input}" "${runfolder}/1_align/1.1_${aligner}"
  checkNtaxa "${runfolder}/1_align/1.1_${aligner}" "${mintaxfilter}" .ali
  checkAlignmentWithRaxml "${runfolder}/1_align/1.1_${aligner}" "${runfolder}/1_align/1.2_${aligner}_check"
else
  mkdir -p "${runfolder}/1_align/1.1_input"
  find "${input}" -name '*.fas' | \
    parallel cp {} "${runfolder}/1_align/1.1_input/{/.}.ali"
  checkNtaxa "${runfolder}/1_align/1.1_input" "${mintaxfilter}" .ali
  checkAlignmentWithRaxml "${runfolder}/1_align/1.1_input" "${runfolder}/1_align/1.2_input_check"
  #rm -rf "${runfolder}/1_align/1.1_input"
fi

# bmge or not
if [ "${dobmge}" ] ; then
  if [ "${doalign}" ] ; then
    runBmge "${runfolder}/1_align/1.2_${aligner}_check/" "${runfolder}/1_align/1.3_${aligner}_check_bmge"
    checkNtaxa "${runfolder}/1_align/1.3_${aligner}_check_bmge" "${mintaxfilter}" .ali
  else
    runBmge "${runfolder}/1_align/1.2_input_check" "${runfolder}/1_align/1.3_input_check_bmge"
    checkNtaxa "${runfolder}/1_align/1.3_input_check_bmge" "${mintaxfilter}" .ali
  fi
fi

# TODO: treeshrink or not
if [ "${dotreeshrink}" ]; then
  mkdir -p "${runfolder}/3_treeshrink"

  # pargenes, fixed model
  if [ "${doalign}" ] ; then
    if [ "${dobmge}" ] ; then
      pargenesFixedModel "${runfolder}/1_align/1.3_${aligner}_check_bmge" "${runfolder}/2_trees/2.1_${aligner}_check_bmge_pargenes"
    else
      pargenesFixedModel "${runfolder}/1_align/1.2_${aligner}_check" "${runfolder}/2_trees/2.1_${aligner}_check_pargenes"
    fi
  else
    if [ "${dobmge}" ] ; then
      pargenesFixedModel "${runfolder}/1_align/1.3_input_check_bmge" "${runfolder}/2_trees/2.1_input_check_bmge_pargenes"
    else
      pargenesFixedModel "${runfolder}/1_align/1.2_input_check" "${runfolder}/2_trees/2.1_input_check_pargenes"
    fi
  fi

  # setup treeshrink
  if [ "${doalign}" ] ; then
    if [ "${dobmge}" ] ; then
      setupTreeshrink "${runfolder}/2_trees/2.1_${aligner}_check_bmge_pargenes/mlsearch_run/results" "${runfolder}/1_align/1.3_${aligner}_check_bmge" "${runfolder}/3_treeshrink/3.1_treeshrink"
    else
      setupTreeshrinkNoBmge "${runfolder}/2_trees/2.1_${aligner}_check_pargenes/mlsearch_run/results" "${runfolder}/1_align/1.2_${aligner}_check" "${runfolder}/3_treeshrink/3.1_treeshrink"
    fi
  else
    if [ "${dobmge}" ] ; then
      setupTreeshrinkBmgeNoAligner "${runfolder}/2_trees/2.1_input_check_bmge_pargenes/mlsearch_run/results" "${runfolder}/1_align/1.3_input_check_bmge" "${runfolder}/3_treeshrink/3.1_treeshrink"
    else
      setupTreeshrinkNoAlignerNoBmge "${runfolder}/2_trees/2.1_input_check_pargenes/mlsearch_run/results" "${runfolder}/1_align/1.2_input_check" "${runfolder}/3_treeshrink/3.1_treeshrink"
    fi
  fi

  # treeshrink
  runTreeshrink "${runfolder}/3_treeshrink/3.1_treeshrink"
  checkNtaxaOutputAli "${runfolder}/3_treeshrink/3.1_treeshrink" "${mintaxfilter}"

  # realign
  if [ "${doalign}" ] ; then
    if [ "${dobmge}" ] ; then
      realignerOutputAli "${runfolder}/3_treeshrink/3.1_treeshrink/" "${runfolder}/1_align/1.4_${aligner}_check_bmge_treeshrink"
    else
      realignerOutputAli "${runfolder}/3_treeshrink/3.1_treeshrink/" "${runfolder}/1_align/1.4_${aligner}_check_treeshrink"
    fi
  else
    if [ "${dobmge}" ] ; then
      realignerOutputAli "${runfolder}/3_treeshrink/3.1_treeshrink/" "${runfolder}/1_align/1.4_input_check_bmge_treeshrink"
    else
      realignerOutputAli "${runfolder}/3_treeshrink/3.1_treeshrink/" "${runfolder}/1_align/1.4_input_check_treeshrink"
    fi
  fi
fi

# TODO: treeshrink or not
if [ "${dotreeshrink}" ]; then
  # pargenes, modeltest, astral
  if [ "${doalign}" ] ; then
    if [ "${dobmge}" ] ; then
      pargenesModeltestAstral "${runfolder}/1_align/1.4_${aligner}_check_bmge_treeshrink" "${runfolder}/2_trees/2.2_${aligner}_check_bmge_treeshrink_pargenes"
    else
      pargenesModeltestAstral "${runfolder}/1_align/1.4_${aligner}_check_treeshrink" "${runfolder}/2_trees/2.2_${aligner}_check_treeshrink_pargenes"
    fi
  else
    if [ "${dobmge}" ] ; then
      pargenesModeltestAstral "${runfolder}/1_align/1.4_input_check_bmge_treeshrink" "${runfolder}/2_trees/2.2_input_check_bmge_treeshrink_pargenes"
    else
      pargenesModeltestAstral "${runfolder}/1_align/1.4_input_check_treeshrink" "${runfolder}/2_trees/2.2_input_check_treeshrink_pargenes"
    fi
  fi
else
  echo "TODO: run pargenes on non-treesrink folders"
fi

# Count
echo -e "\n## ATPW [$(date "+%F %T")]: Count sequences in output" | tee -a "${logfile}"
count

# Create Readme
echo -e "\n## ATPW [$(date "+%F %T")]: Create summary README.md file" | tee -a "${logfile}"
createReadme

# End
echo -e "\n## ATPW [$(date "+%F %T")]: Reached end of the script\n" 2>&1 | tee -a "${logfile}"

exit 0

