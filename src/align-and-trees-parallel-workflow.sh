#!/bin/bash -l

# Last modified: tis apr 02, 2024  07:26
# Sign: JN

set -uo pipefail

# Default paths to software
BMGEJAR="${BMGEJAR:-${HOME}/Documents/GIT/Align-and-trees-parallel-workflow/BMGE-1.12/BMGE.jar}" # <<<<<<<<<< CHANGE HERE
PARGENES="${PARGENES:-${HOME}/Documents/GIT/Align-and-trees-parallel-workflow/ParGenes/pargenes/pargenes.py}" # <<<<<<<<<< CHANGE HERE
TREESHRINK="${TREESHRINK:-${HOME}/Documents/GIT/Align-and-trees-parallel-workflow/TreeShrink/run_treeshrink.py}" # <<<<<<<<<< CHANGE HERE
TRIMAL="${TRIMAL:-${HOME}/Documents/GIT/Align-and-trees-parallel-workflow/trimal/source/trimal}" # <<<<<<<<<< CHANGE HERE
fastagap='fastagap.pl'  # Assumed to be in the path

# Varia
version="0.9.4"
nprocs=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null)
ncores="${nprocs}"  # TODO: Do we need to adjust?
logfile=
datatype='nt'

# Aligner
aligner='mafft'  # Name of aligner, not path to binary
alignerbin='mafft'  # Assumed to be in path
threadsforaligner='2'  # TODO: Adjust?
alignerbinopts="--auto --thread ${threadsforaligner} --quiet"

# Realigner
realigner='mafft'  # Name of realigner, not path to binary
realignerbinopts="${alignerbinopts}"
#threadsforrealigner='2' # TODO: Adjust?

# Alignment filter
alifilter='bmge'  # or "trimal"
alifilteroptions=
bmgeoptions=  # Consider changing default to '-h 0.7' (cf. Rokas' ClipKIT program)
datatypeforbmge='DNA'
datatypeforbmgeAA='AA'
trimaloptions='-automated1'

# Fasta filter
maxinvariantsites=100.00  # percent
mintaxfilter=4  # Min nr of seqs for keeping file

# Treeshrink
treeshrinkoptions=

# ParGenes
raxmlng='raxml-ng'
bootstrapreps=0
modelforpargenesfixed='GTR+G8+F'
modelforpargenesfixedAA='LG+G8+F'
modelforraxmltest='GTR'
modelforraxmltestAA='LG'
modeltestcriterion="BIC"
modeltestperjobcores='4'  # TODO: Adjust? This value needs to be at least 4!

# Aster
asterbin='astral'  # Name of prog, not path to binary

# Usage
function usage {
cat << End_Of_Usage

$(basename "$0") version ${version}

What:
    Phylogenetics in parallel

    Performs the following steps:

    1. Do multiple sequence alignment (optional)
    2. Filter using BMGE or TrimAl (optional)
    3. Filter using TreeShrink (optional)
    4. Estimate gene trees with raxml-ng using
       automatic model selection
    5. Estimate species tree using ASTER/ASTRAL (optional)

By:
    Johan Nylander

Usage:
    $(basename "$0") -d nt|aa [options] infolder outfolder

Options:
    -d type   -- Specify data type: nt or aa. (Mandatory)
    -n number -- Specify the number of threads. Default: ${ncores}
    -m crit   -- Model test criterion: BIC, AIC or AICC. Default: ${modeltestcriterion}
    -i number -- Number of bootstrap iterations. Default: ${bootstrapreps}
    -f number -- Minimum number of taxa when filtering alignments. Default: ${mintaxfilter}
    -s prog   -- Specify ASTRAL/ASTER program: astral.jar, astral, astral-pro, or astral-hybrid. Default: ${asterbin}
    -l prog   -- Specify alignment filter software: bmge or trimal. Default: ${alifilter}
    -b opts   -- Specify options for alignment-filter program. Multiple options needs to be quoted. Default: program defaults
    -t opts   -- Specify options for TreeShrink. Multiple options needs to be quoted. Default: ${treeshrinkoptions:-"program defaults"}.
    -a opts   -- Specify options for aligner (default ${aligner}. Multiple options needs to be quoted. Default (for ${aligner}): ${alignerbinopts}
    -A        -- Do not run aligner (assume aligned input)
    -B        -- Do not run alignment-filter program
    -T        -- Do not run TreeShrink
    -S        -- Do not run ASTER/ASTRAL (no species-tree estimation)
    -v        -- Print version. See output of -c for other software versions
    -c        -- Print citations and software versions
    -h        -- Print help message

Examples:
    $(basename "$0") -d nt -n 8 data out
    $(basename "$0") -d nt -A -i 100 aligned-data out

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

License:
    Copyright (C) 2022-2024 nylander <johan.nylander@nrm.se>
    Distributed under terms of the MIT license.

End_Of_Usage

}

function citations {
  # Print software version with citation
  declare -A version_dict="$(getVersions)"
  declare -A citation_dict="$(getCitations)"
  for key in  "${!version_dict[@]}" ; do
    echo "- $key ${version_dict[$key]} ${citation_dict[$key]}"
  done
}

#function citations {
#  local rp
#  rp=$(realpath "${PARGENES}")
#  local pb
#  pb=$(dirname "${rp}")
#  local pbins
#  pbins="${pb}/pargenes_binaries"
#  declare -A Versions=(
#    ['atpw']=$($0 -v)
#    ['astral']=$("${pbins}"/astral-hybrid 2>&1 | grep -m 1 'Version' | awk '{print $2}' | sed 's/^v//')
#    ['astral-hybrid']=$("${pbins}"/astral-hybrid 2>&1 | grep -m 1 'Version' | awk '{print $2}' | sed 's/^v//')
#    ['astral-pro']=$("${pbins}"/astral-pro 2>&1 | grep -m 1 'Version' | awk '{print $2}' | sed 's/^v//')
#    ['astral.jar']=$(java -jar "${pbins}"/astral.jar --help 2>&1 | grep -m 1 'This is ASTRAL version' | awk '{print $NF}')
#    ['bmge']=$(java -jar "${BMGEJAR}" -? 2>&1 | grep 'BMGE (version' | sed 's/)//' | awk '{print $3}')
#    ['fastagap']=$("${fastagap}" --version)
#    ['mafft']=$("${alignerbin}" --version 2>&1 | awk '{print $1}' | sed 's/^v//')
#    ['modeltest-ng']=$("${pbins}"/modeltest-ng --version 2>&1 | grep -m 1 '^modeltest' | awk '{print $2}')
#    ['parallel']=$(parallel --version 2>&1 | head -1 | awk '{print $3}')
#    ['pargenes']=$("${PARGENES}" --version 2>&1 | awk '{print $2}' | sed 's/[(|)|v]//g')
#    ['raxml-ng']=$("${raxmlng}" 2>&1 | grep 'RAxML-NG' | awk '{print $3}')
#    ['treeshrink']=$("${TREESHRINK}" --version)
#    ['trimal']=$("${TRIMAL}" --version 2>&1 | grep . | awk '{print $2}' | sed 's/^v//')
#  )
#
#cat << End_Of_Citations
#- [ATPW v. ${Versions[atpw]}](https://github.com/nylander/Align-and-trees-parallel-workflow)
#  Nylander, J. A. A. 2022. ATPW - Align and trees parallel workflow. Program
#  distributed by the author.
#  <https://github.com/nylander/Align-and-trees-parallel-workflow>
#- [astral v. ${Versions[astral]}](https://github.com/chaoszhang/ASTER) Zhang, C., and S. Mirarab. 2022.
#  Weighting by Gene Tree Uncertainty Improves Accuracy of Quartet-based Species
#  Trees. Mol. Biol. Evol. 39:msac215. <https://doi.org/10.1093/molbev/msac215>
#- [astral-pro v. ${Versions[astral-pro]}](https://github.com/chaoszhang/ASTER) Zhang, C., and S. Mirarab. 2022.
#  Weighting by Gene Tree Uncertainty Improves Accuracy of Quartet-based Species
#  Trees. Mol. Biol. Evol. 39:msac215. <https://doi.org/10.1093/molbev/msac215>
#- [astral-hybrid v. ${Versions[astral-hybrid]}](https://github.com/chaoszhang/ASTER) Zhang, C., and S. Mirarab. 2022.
#  Weighting by Gene Tree Uncertainty Improves Accuracy of Quartet-based Species
#  Trees. Mol. Biol. Evol. 39:msac215. <https://doi.org/10.1093/molbev/msac215>
#- [astral.jar v. ${Versions[astral.jar]}](https://github.com/smirarab/ASTRAL) Zhang, C., M. Rabiee, E.
#  Sayyari, and S. Mirarab. 2018. ASTRAL-III: Polynomial Time Species Tree
#  Reconstruction from Partially Resolved Gene Trees. BMC Bioinformatics
#  19(S6):153. <https://doi.org/10.1186/s12859-018-2129-y>
#- [BMGE v. ${Versions[bmge]}](http://ftp.pasteur.fr/pub/gensoft/projects/BMGE/) Criscuolo, A. and S.
#  Gribaldo. 2010. BMGE (Block Mapping and Gathering with Entropy): a new
#  software for selection of phylogenetic informative regions from multiple
#  sequence alignments. BMC Evol. Biol. 10:210.
#  <https://doi.org/10.1186/1471-2148-10-210>
#- [fastagap v. ${Versions[fastagap]}](https://github.com/nylander/fastagap) Nylander, J. A. A. 2019.
#  FastaGap. Software distributed by the author.
#  <https://github.com/nylander/fastagap>
#- [GNU parallel v. ${Versions[parallel]}](https://www.gnu.org/software/parallel) Tange, O. 2021. GNU
#  Parallel 20210822 ('Kabul'). Zenodo. <https://doi.org/10.5281/zenodo.5233953>
#- [MAFFT v. ${Versions[mafft]}](https://mafft.cbrc.jp/alignment/software/) Katoh, K. and D. M.
#  Standley. 2013. MAFFT Multiple Sequence Alignment Software Version 7:
#  Improvements in Performance and Usability. Mol. Biol. Evol. 30:772-780.
#  <https://doi.org/10.1093/molbev/mst010>
#- [ModelTest-NG v. ${Versions[modeltest-ng]}](https://github.com/ddarriba/modeltest) Darriba, D., D. Posada,
#  A. M. Kozlov, A. Stamatakis, B. Morel, and T. Flouri. 2020. ModelTest-NG: a
#  new and scalable tool for DNA and protein model selection. Mol. Biol. Evol.
#  37:291-294. <https://doi.org/10.1093/molbev/msz189>
#- [ParGenes v. ${Versions[pargenes]}](https://github.com/BenoitMorel/ParGenes) Benoit Morel, B., A. M.
#  Kozlov, and A. Stamatakis. 2018. ParGenes: a tool for massively parallel
#  model selection and phylogenetic tree inference on thousands of genes.
#  Bioinformatics 35:1771-1773. <https://doi.org/10.1093/bioinformatics/bty839>
#- [RaxML-NG v. ${Versions[raxml-ng]}](https://github.com/amkozlov/raxml-ng) Kozlov, A. M., D. Darriba,
#  T. Flouri, B. Morel, and A. Stamatakis. 2019. RAxML-NG: A fast, scalable, and
#  user-friendly tool for maximum likelihood phylogenetic inference.
#  Bioinformatics 35:4453-4455. <https://doi.org/10.1093/bioinformatics/btz305>
#- [TreeShrink v. ${Versions[treeshrink]}](https://github.com/uym2/TreeShrink) Mai, U., and S. Mirarab.
#  2018. TreeShrink: Fast and Accurate Detection of Outlier Long Branches in
#  Collections of Phylogenetic Trees. BMC Genomics 19(S5):272.
#  <https://doi.org/10.1186/s12864-018-4620-2>
#- [TrimAL v. ${Versions[trimal]}](https://github.com/inab/trimal) Capella-Gutierrez, S., J. M.
#  Silla-Martinez, and T. Gabaldon. 2009. trimAl: a tool for automated alignment
#  trimming in large-scale phylogenetic analyses. Bioinformatics 25:1972-1973.
#  <https://doi.org10.1093/bioinformatics/btp348>
#
#End_Of_Citations
#
#}

getVersions() {
  ## Get software versions
  # Use: declare -A dict="$(getVersions)"; "${dict[$key]}"
  ## Note: current modeltest-ng version (from pargenes) is "x.y.z"!
  local rp
  rp=$(realpath "${PARGENES}")
  local pb
  pb=$(dirname "${rp}")
  local pbins
  pbins="${pb}/pargenes_binaries"
  declare -A dict=(
    ['astral']=$("${pbins}"/astral -v 2>&1 | awk '$1 == "Version:"{print $2}')
    ['astral-hybrid']=$("${pbins}"/astral-hybrid -v 2>&1 | awk '$1 == "Version:"{print $2}')
    ['astral-pro']=$("${pbins}"/astral-pro -v 2>&1 | awk '$1 == "Version:"{print $2}')
    ['astral.jar']=$(java -jar "${pbins}"/astral.jar --help 2>&1 | grep 'This is ASTRAL version' | awk '{print "v"$NF}')
    ['bmge']=$(java -jar "${BMGEJAR}" -? | sed -n 's/.*(version \([0-9\.]*\).*/v\1/p')
    ['fastagap']=$("${fastagap}" -v | sed 's/^/v/')
    ['mafft']=$(mafft --version  2>&1 | awk '{print $1}')
    ['modeltest-ng']=$("${pbins}"/modeltest-ng --version | awk '$1 ~ /^modeltest/{print "v"$2;exit}')
    ['parallel']=$(parallel --version | head -1 | awk '{print "v"$NF}')
    ['pargenes']=$("${PARGENES}" --version | sed 's/.*ParGenes (v\([0-9\.]*\).*/v\1/')
    ['raxml-ng']=$("${pbins}"/raxml-ng -v | grep '^RAxML-NG v.' | awk '{print "v"$3}')
    ['treeshrink']=$("${TREESHRINK}" --version | sed 's/^/v/')
    ['trimal']=$("${TRIMAL}" --version | grep . | awk '{print $2}')
  )
  echo '('
  for key in  "${!dict[@]}" ; do
    echo "['$key']='${dict[$key]}'"
  done
  echo ')'
}

getCitations() {
  ## Get software versions
  # Use: declare -A dict="$(getCitations)"; "${dict[$key]}"
  local rp
  rp=$(realpath "${PARGENES}")
  local pb
  pb=$(dirname "${rp}")
  local pbins
  pbins="${pb}/pargenes_binaries"
  declare -A dict=(
    ['treeshrink']='[Mai & Mirarab. 2018. BMC Genomics 19:272](https://doi.org/10.1186/s12864-018-4620-2)'
    ['bmge']='[Criscuolo & Gribaldo. 2010. BMC Evolutionary Biology 10:210](https://doi.org/10.1186/1471-2148-10-210)'
    ['mafft']='[Katoh & Standley. 2013. (MBE 30:772-780)](https://doi.org/10.1093/molbev/mst010)'
    ['parallel']='[Tange. 2018. GNU Parallel 2018, March 2018](https://doi.org/10.5281/zenodo.1146014)'
    ['fastagap']='[Nylander, 2019. Software published by the author.](https://github.com/nylander/fastagap)'
    ['trimal']='[Capella-Gutierrez et al. 2009. Bioinformatics 25:1972-1973](https://10.1093/bioinformatics/btp348)'
    ['pargenes']='[Morel et al. 2018. Bioinformatics 35:1771-1773](https://doi.org/10.1093/bioinformatics/bty839)'
    ['raxml-ng']='[Kozlov et al. 2019. Bioinformatics 35:4453-4455](https://doi.org/10.1093/bioinformatics/btz305)'
    ['astral.jar']='[Zhang et al. 2018. BMC Bioinformatics 19:153](https://doi.org/10.1186/s12859-018-2129-y)'
    ['astral']='[Zhang & Mirarab. 2022. MBE 39:msac215, ](https://doi.org/10.1093/molbev/msac215)'
    ['astral-pro']='[Zhang & Mirarab. 2022. Bioinformatics 38:4949-4950](https://doi.org/10.1093/bioinformatics/btac620)'
    ['astral-hybrid']='[Zhang & Mirarab. 2022. MBE 39:msac215, ](https://doi.org/10.1093/molbev/msac215)'
    ['modeltest-ng']='[Darriba et al. 2020. MBE 37:291–294](https://doi.org/10.1093/molbev/msz189)'
  )
  echo '('
  for key in  "${!dict[@]}" ; do
    echo "['$key']='${dict[$key]}'"
  done
  echo ')'
}


# Arguments and defaults
doalign=1
doalifilter=1
dotreeshrink=1
doaster=1
doboot=
dobmge=1
dotrimal=
Aflag=
Bflag=
Sflag=
Tflag=
aflag=
bflag=
dflag=
fflag=
iflag=
lflag=
mflag=
nflag=
sflag=
tflag=
while getopts 'ABSTa:b:d:f:i:l:m:n:s:t:vhc' OPTION
do
  case $OPTION in
  A) Aflag=1
     doalign=
     ;;
  B) Bflag=1
     doalifilter=
     ;;
  S) Sflag=1
     doaster=
     ;;
  T) Tflag=1
     dotreeshrink=
     ;;
  a) aflag=1
     aval="$OPTARG"
     ;;
  b) bflag=1
     bval="$OPTARG"
     ;;
  d) dflag=1
     dval="$OPTARG"
     ;;
  f) fflag=1
     fval="$OPTARG"
     ;;
  i) iflag=1
     ival="$OPTARG"
     ;;
  l) lflag=1
     lval="$OPTARG"
     ;;
  m) mflag=1
     mval="$OPTARG"
     ;;
  n) nflag=1
     nval="$OPTARG"
     ;;
  s) sflag=1
     sval="$OPTARG"
     ;;
  t) tflag=1
     tval="$OPTARG"
     ;;
  v) echo "${version}"
     exit
     ;;
  h) usage
     exit
     ;;
  c) citations
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
  export logfile
  start=$(date "+%F %T")
  export start
  echo -e "\n## ATPW [$start]: Start ATPW v${version}" 2>&1 | tee "${logfile}"
  echo -e "\n## ATPW [$(date "+%F %T")]: Created output folder ${runfolder}" 2>&1 | tee -a "${logfile}"
  echo -e "\n## ATPW [$(date "+%F %T")]: Created logfile ${logfile}" 2>&1 | tee -a "${logfile}"
fi

if [ -d "${input}" ] ; then
  nfas=$(find "${input}" -name '*.fas' | wc -l) # TODO: allow any suffix.
  if [ "${nfas}" -gt 1 ] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]: Found ${nfas} .fas files in folder ${input}" 2>&1 | tee -a "${logfile}"
    mkdir -p "${runfolder}/1_align/1.1_input"
    find "${input}" -name '*.fas' | \
      parallel cp {} "${runfolder}/1_align/1.1_input/{/.}.ali"
    for f in "${runfolder}"/1_align/1.1_input/*.ali ; do
      g=$(basename "${f}" .ali)
      if [[ $g == *.* ]] ; then # replace periods in file names
        h=${g//./_}
        mv "${f}" "${runfolder}"/1_align/1.1_input/"${h}".ali
      fi
    done
  else
    echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! Could not find .fas files in folder ${input}" 2>&1 | tee -a "${logfile}"
    exit 1
  fi
else
  echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! Folder ${input} can not be found" 2>&1 | tee -a "${logfile}"
  exit 1
fi

## Check options
if [ ! "${dflag}" ] ; then
  echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! Need to supply data type ('nt' or 'aa') with '-d'" 2>&1 | tee -a "${logfile}"
  exit 1
elif [ "${dflag}" ] ; then
  lcdval=${dval,,} # to lowercase
  if [[ "${lcdval}" != @(nt|aa) ]] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! -d should be 'nt' or 'aa'" 2>&1 | tee -a "${logfile}"
    exit 1
  else
    datatype="${lcdval}"
  fi
fi
if [ "${datatype}" = 'aa' ] ; then
  datatypeforbmge="${datatypeforbmgeAA}"
  modelforraxmltest="${modelforraxmltestAA}"
  modelforpargenesfixed="${modelforpargenesfixedAA}"
fi
if [ "${Aflag}" ] ; then
  echo -e "\n## ATPW [$(date "+%F %T")]: Data is assumed to be aligned: skipping first alignment step" 2>&1 | tee -a "${logfile}"
fi
if [ "${Bflag}" ] ; then
  echo -e "\n## ATPW [$(date "+%F %T")]: Skipping the ${alifilter} filtering step" 2>&1 | tee -a "${logfile}"
fi
if [ "${Tflag}" ] ; then
  echo -e "\n## ATPW [$(date "+%F %T")]: Skipping the TreeShrink step" 2>&1 | tee -a "${logfile}"
fi
if [ "${aflag}" ] ; then
  alignerbinopts="${aval}"
fi
if [ "${bflag}" ] ; then
  alifilteroptions="${bval}"
fi
if [ "${lflag}" ] ; then
  lclval=${lval,,} # to lowercase
  if [[ "${lclval}" != @(bmge|trimal) ]] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! -l should be 'bmge' or 'trimal'" 2>&1 | tee -a "${logfile}"
    exit 1
  else
    alifilter="${lclval}"
  fi
fi
if [[ "${alifilter}" == 'bmge' ]] ; then
  dobmge=1
  dotrimal=
  if [ "${alifilteroptions}" ] ; then
    bmgeoptions="${alifilteroptions}"
  fi
elif [[ "${alifilter}" == 'trimal' ]] ; then
  dotrimal=1
  dobmge=
  if [ "${alifilteroptions}" ] ; then
    trimaloptions="${alifilteroptions}"
  fi
fi
if [ "${tflag}" ] ; then
  treeshrinkoptions="${tval}"
fi
if [ "${mflag}" ] ; then
  ucmval=${mval^^} # to upper case
  if [[ "${ucmval}" != @(BIC|AIC|AICC) ]] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! -m should be 'BIC', 'AIC', or 'AICC'" 2>&1 | tee -a "${logfile}"
  else
    modeltestcriterion="${ucmval}"
  fi
fi
if [ "${iflag}" ] ; then
  bootstrapreps="${ival}"
  if [[ "${bootstrapreps}" -gt 0 ]] ; then
    doboot=1
  else
    doboot=
  fi
fi
if [ "${sflag}" ] ; then
  lcsval=${sval,,} # to lower case
  if [[ "${lcsval}" != @(astral.jar|astral|astral-hybrid|astral-pro) ]] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]: ERROR! -m should be 'astral.jar', 'astral', 'astral-hybrid', or 'astral-pro'" 2>&1 | tee -a "${logfile}"
  else
    asterbin="${lcsval}"
  fi
fi
if [ "${doboot}" ] && [ ! "${sflag}" ] ; then
  asterbin="astral-hybrid"
  echo -e "\n## ATPW [$(date "+%F %T")]: Will use ${asterbin} on bootstrap trees (use -s to change)" 2>&1 | tee -a "${logfile}"
fi
if [ "${Sflag}" ] ; then
  echo -e "\n## ATPW [$(date "+%F %T")]: Skipping the ASTER/ASTRAL step" 2>&1 | tee -a "${logfile}"
  asterbin='NOASTER'
fi
if [ "${nflag}" ] ; then
  nthreads="${nval}"
  ncores="${nthreads}" # TODO: differentiate these variables
fi
if [ "${fflag}" ] ; then
  mintaxfilter="${fval}"
fi

# Needed for some bash functions
export runfolder
export aligner
export realigner

# Functions
printVersions() {
  # Print program versions as a markdown table
  # TODO: add reference as an additional column
  local steps="$1"
  declare -A v_dict="$(getVersions)"
  echo ""
  echo -e "## Software versions"
  echo -e "| tool | version |"
  echo -e "| --- | --- |"
  for prog in ${steps//,/} ; do
    echo -e "| $prog | ${v_dict[$prog]} |"
  done
  for prog in modeltest-ng pargenes fastagap parallel ; do
    echo -e "| $prog | ${v_dict[$prog]} |"
  done
}
export -f printVersions

checkNtaxaInFasta() {
  # Function for checking and removing fasta files with less than N taxa
  # If other max N, use, e.g., "parallel checkNtaxaInFasta {} 10"
  f=$1
  n=${2:-4} # default 4
  b=$(basename "${f}")
  ntax=$(grep -c '>' "${f}")
  if [[ "${ntax}" -lt $n ]] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]: ${b} have less than ${n} taxa: (${ntax}). Removing!" >> "${logfile}" 2>&1
    rm -v "${f}"
  fi
}
export -f checkNtaxaInFasta

align() {
  # Alignments with mafft. Convert lower case mafft output to uppercase.
  # Input: inputfolder/*.fas
  # Output: 1_align/1.1_mafft/*.ali
  # Call: align "${input}" "${runfolder}/1_align/1.1_${aligner}"
  # TODO: use threads.
  local inputfolder="$1"
  local outputfolder="$2"
  echo -e "\n## ATPW [$(date "+%F %T")]: Align with ${aligner} ${alignerbinopts}" 2>&1 | tee -a "${logfile}"
  mkdir -p "${outputfolder}"
  find "${inputfolder}" -type f -name '*.ali' | \
    parallel ''"${alignerbin}"' '"${alignerbinopts}"' {} | '"sed '/>/ ! s/[a-z]/\U&/g'"' > '"${outputfolder}"'/{/.}.ali' >> "${logfile}" 2>&1
}

checkAlignments() {
  # Check alignments with raxml-ng
  # Input: folder/*.ali
  # Output: Removes files in input folder
  # Call: checkAlignment "${runfolder}/1_align/1.1_${aligner}" "${maxinvariantsites}"
  # TODO:
  local inputfolder="$1"
  local maxinvariant=${2:-100} # default 100 (i.e., remove if Invariable sites: 100.00 %)
  echo -e "\n## ATPW [$(date "+%F %T")]: Check if alignments is readable by raxml-ng" | tee -a "${logfile}"
  find  "${inputfolder}" -type f -name '*.ali' | \
    parallel ''"${raxmlng}"' --check --msa {} --threads 1 --model '"${modelforraxmltest}"'' >> "${logfile}" 2>&1
  find "${inputfolder}" -type f -name '*.log' | \
    parallel 'if grep -q "^ERROR" {} ; then echo "## ATPW ['"$(date "+%F %T")"']: Removing {=s/\.raxml\.log//=}"; rm -v {=s/\.raxml\.log//=} ; fi' >> "${logfile}" 2>&1
  echo -e "\n## ATPW [$(date "+%F %T")]: Check and remove if any files have more or equal than ${maxinvariant} percent invariable sites" 2>&1 | tee -a "${logfile}"
  find "${inputfolder}" -type f -name '*.log' | \
    parallel 'removeInvariant {} '"${maxinvariant}"''
  if [ ! "$(find "${inputfolder}" -type f -name '*.ali')" ]; then
    echo -e "\n## ATPW [$(date "+%F %T")]:checkAlignments WARNING! No alignment files left in ${inputfolder}. Quitting." | tee -a "${logfile}"
    exit 1
  fi
  rm "${inputfolder}"/*.log
  rm "${inputfolder}"/*.raxml.reduced.phy
}

runBmge() {
  # Run BMGE
  # Input: 1_align/1.2_mafft/*.mafft.ali (symlinks)
  # Output: 1_align/1.3_mafft_bmge/*.ali
  # Call: runBmge "${runfolder}/1_align/1.2_${aligner}_check/" "${runfolder}/1_align/1.3_${aligner}_${alifilter}"
  # TODO:
  local inputfolder="$1"
  local outputfolder="$2"
  mkdir -p "${outputfolder}"
  cd "${outputfolder}" || exit
  if [ "${bmgeoptions}" ] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]: Run BMGE with options ${bmgeoptions}" | tee -a "${logfile}"
    find -L "${inputfolder}/" -type f -name '*.ali' | \
      parallel 'java -jar '"${BMGEJAR}"' -i {} '"${bmgeoptions}"' -t '"${datatypeforbmge}"' -of {/.}.ali' >> "${logfile}" 2>&1
  else
    echo -e "\n## ATPW [$(date "+%F %T")]: Run BMGE with default options" | tee -a "${logfile}"
    find -L "${inputfolder}/" -type f -name '*.ali' | \
      parallel 'java -jar '"${BMGEJAR}"' -i {} -t '"${datatypeforbmge}"' -of {/.}.ali' >> "${logfile}" 2>&1
  fi
  cd .. || exit
}

runTrimal() {
  # Run TrimAl
  # Input: 1_align/1.2_${aligner}/*.mafft.ali (symlinks)
  # Output: 1_align/1.3_${aligner}_trimal/*.ali
  # Call: runTrimal "${runfolder}/1_align/1.2_${aligner}_check/" "${runfolder}/1_align/1.3_${aligner}_${alifilter}"
  # TODO:
  local inputfolder="$1"
  local outputfolder="$2"
  mkdir -p "${outputfolder}"
  cd "${outputfolder}" || exit
  if [ "${trimaloptions}" ] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]: Run TriMal with options ${trimaloptions}" | tee -a "${logfile}"
    find -L "${inputfolder}/" -type f -name '*.ali' | \
      parallel ''"${TRIMAL}"' -in {} '"${trimaloptions}"' -out {/.}.ali' >> "${logfile}" 2>&1
  else
    echo -e "\n## ATPW [$(date "+%F %T")]: Run TrimAL with default options" | tee -a "${logfile}"
    find -L "${inputfolder}/" -type f -name '*.ali' | \
      parallel ''"${TRIMAL}"' -in {} -out {/.}.ali' >> "${logfile}" 2>&1
  fi
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
  if [ ! "$(find "${inputfolder}" -maxdepth 1 -type f -name "*${suffix}")" ] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]:checkNtaxa WARNING! No ${suffix} files left in ${inputfolder}. Quitting." | tee -a "${logfile}"
    exit 1
  fi
}

checkNtaxaOutputAli() {
  # Check and remove if any of the output.ali files have less than 4 taxa
  # Input: 1_align/1.3_mafft_bmge/*.mafft.ali
  # Output: remove /1_align/1.3_mafft_bmge/*.ali files
  # Call: checkNtaxaOutputAli 1_align/1.3_mafft_bmge/ 4
  # TODO: Use when we have other .ali files except the output.ali from treeshrink
  local inputfolder="$1"
  local min="$2"
  echo -e "\n## ATPW [$(date "+%F %T")]: Check and remove if any files have less than ${mintaxfilter} taxa" 2>&1 | tee -a "${logfile}"
  find "${inputfolder}" -type f -name 'output.ali' | \
    parallel 'checkNtaxaInFasta {} '"${min}"''>> "${logfile}" 2>&1
  if [ ! "$(find "${inputfolder}" -type f -name 'output.ali')" ]; then
    echo -e "\n## ATPW [$(date "+%F %T")]:checkNtaxaOutputAli WARNING! No output.ali files left in ${inputfolder}. Quitting." | tee -a "${logfile}"
    exit 1
  fi
}

removeInvariant() {
  # Remove file if alignment has more than (or equal to) maxinvariantsites percent invariant sites
  # Input: Alignment (*.ali)
  # Output: REMOVES file
  # Call: from checkInvariant function
  local infile="$1"
  local maxi=${2:-100}
  local alifile="${infile%.raxml.log}"
  local aliname
  aliname=$(basename "${alifile}")
  if grep -q "^Invariant sites" "${infile}" ; then
    perc=$(grep 'Invariant sites:' "${infile}" | grep -Eo "[0-9]+\.[0-9]+")
    if [ "$(echo "${perc} >= ${maxi}" | bc -l)" -eq 1 ]; then
      echo "## ATPW [$(date "+%F %T")]: ${aliname} have ${perc} percent invariant sites: Removing!" >> "${logfile}"
      rm "${alifile}"
    fi
  fi
}
export -f removeInvariant

pargenesFixedModel() {
  # Run pargenes with fixed model
  # Input: /1_align/1.3_mafft_check_bmge
  # Output: /2_trees/2.1_mafft_check_bmge_pargenes
  # Call: pargenesFixedModel "${runfolder}/1_align/1.3_mafft_check_bmge" "${runfolder}/2_trees/2.1_mafft_check_bmge_pargenes"
  # TODO: Create the "${runfolder}/2_trees" outside the function!
  local inputfolder="$1"
  local outputfolder="$2"
  echo -e "\n## ATPW [$(date "+%F %T")]: Run pargenes with fixed model (${modelforpargenesfixed})" 2>&1 | tee -a "${logfile}"
  "${PARGENES}" \
    --alignments-dir "${inputfolder}" \
    --output-dir "${outputfolder}" \
    --cores "${ncores}" \
    --datatype "${datatype}" \
    --raxml-global-parameters-string "--model ${modelforpargenesfixed}" >> "${logfile}" 2>&1
}

setupTreeshrink() {
 # Setup data for TreeShrink
 # Input: tmp_treeshrink
 # Output:
 # Call: setupTreeshrink "${runfolder}/2_trees/2.1_mafft_alifilter_pargenes/mlsearch_run/results" "${runfolder}/1_align/1.3_mafft_alifilter" "${runfolder}/tmp_treeshrink"
 # TODO: Make sure this function works with all arg combos
 inputfolderone="$1"     # where to look for trees
 inputfoldertwo="$2"     # where to look for alignments
 outputfolderthree="$3"  # output
 export inputfolderone
 export inputfoldertwo
 export outputfolderthree
 mkdir -p "${outputfolderthree}"
 copyAndConvert() {
   local f=
   f=$(basename "$1" .raxml.bestTree)
   mkdir -p "${outputfolderthree}/${f}"
   ln -s "$1" "${outputfolderthree}/${f}/raxml.bestTree"
   local a=${f/_ali/\.ali}
   ln -s "${inputfoldertwo}/${a}" "${outputfolderthree}/${f}/alignment.ali"
 }
 export -f copyAndConvert
 find "${inputfolderone}" -type f -name '*.raxml.bestTree' | \
   parallel copyAndConvert {} >> "${logfile}" 2>&1
}

runTreeshrink() {
  # Run TreeShrink
  # Input: tmp_treeshrink
  # Output:
  # Call: runTreeshrink  "${runfolder}/tmp_treeshrink"
  local inputfolder="$1"
  if [ "${treeshrinkoptions}" ] ; then
    echo -e "\n## ATPW [$(date "+%F %T")]: Run treeshrink" 2>&1 | tee -a "${logfile}"
    "${TREESHRINK}" \
      --indir "${inputfolder}" \
      --tree 'raxml.bestTree' \
      --alignment "alignment.ali" \
      "${treeshrinkoptions}" >> "${logfile}" 2>&1
  else
    echo -e "\n## ATPW [$(date "+%F %T")]: Run treeshrink" 2>&1 | tee -a "${logfile}"
    "${TREESHRINK}" \
      --indir "${inputfolder}" \
      --tree 'raxml.bestTree' \
      --alignment "alignment.ali" >> "${logfile}" 2>&1
  fi
}

realignerOutputAli() {
  # Realign using realigner (search for "output.ali" files). Convert mafft output to upper case.
  # Input: tmp_treeshrink/
  # Output: 1_align/1.4_aligner_alifilter_treeshrink
  # Call: realignerOutputAli  "${runfolder}/tmp_treeshrink/" "${runfolder}/1_align/1.4_aligner_alifilter_treeshrink"
  # TODO: Check if I can avoid the specific search for "output.ali" (there are other .ali files in in the input folder, but they are symlinks!)
  local inputfolder="$1"
  local outputfolder="$2"
  echo -e "\n## ATPW [$(date "+%F %T")]: Realign using ${realigner} ${realignerbinopts}" 2>&1 | tee -a "${logfile}"
  mkdir -p "${outputfolder}"
  find "${inputfolder}" -type f -name 'output.ali' | \
    parallel 'b=$(basename {//} .ali); '"${realigner}"' '"${realignerbinopts}"' <('"${fastagap}"' {}) | '"sed '/>/ ! s/[a-z]/\U&/g'"' > '"${outputfolder}"'/"${b/_ali/.ali}"' >> "${logfile}" 2>&1
}

realignerAli() {
  # Realign using realigner (search for ".ali" files). Convert mafft output to upper case.
  # Input:
  # Output:
  # Call: realignerOutputAli  "${runfolder}/tmp_treeshrink/" "${runfolder}/1_align/1.4_mafft_bmge_treeshrink"
  # TODO: Check if I can avoid the specific search for "output.ali" (there are other .ali files in in the input folder, but they are symlinks!)
  local inputfolder="$1"
  local outputfolder="$2"
  echo -e "\n## ATPW [$(date "+%F %T")]: Realign using ${realigner}" 2>&1 | tee -a "${logfile}"
  mkdir -p "${outputfolder}"
  find "${inputfolder}" -type f -name '*.ali' | \
    parallel 'b=$(basename {//} .ali); '"${realigner}"' '"${realignerbinopts}"' <('"${fastagap}"' {}) | sed '/>/ ! s/[a-z]/\U&/g' > '"${outputfolder}"'/"${b//_/\.}"' >> "${logfile}" 2>&1
}

pargenesModeltestAstral() {
  # Run pargenes with modeltest, finish with ASTER/ASTRAL
  # Input: /1_align/1.3_mafft_check_bmge
  # Output: /2_trees/2.1_mafft_check_bmge_pargenes
  # Call: pargenesModeltestAstral "${runfolder}/1_align/1.4_mafft_check_bmge_treeshrink" "${runfolder}/2_trees/2.2_mafft_check_bmge_treeshrink_pargenes" "${asterbin}"
  # TODO:
  local inputfolder="$1"
  local outputfolder="$2"
  local astbin="$3"
  if [ "${astbin}" = 'NOASTER' ] ; then
    if [ "${doboot}" ] ; then
      echo -e "\n## ATPW [$(date "+%F %T")]: Run pargenes with model selection and bootstrap (i=${bootstrapreps})" 2>&1 | tee -a "${logfile}"
      "${PARGENES}" --alignments-dir "${inputfolder}" --output-dir "${outputfolder}" \
        --cores "${ncores}" --datatype "${datatype}" \
        --use-modeltest --modeltest-criteria "${modeltestcriterion}" --modeltest-perjob-cores "${modeltestperjobcores}" \
        --autoMRE -b "${bootstrapreps}" >> "${logfile}" 2>&1
    else
      echo -e "\n## ATPW [$(date "+%F %T")]: Run pargenes with model selection" 2>&1 | tee -a "${logfile}"
      "${PARGENES}" --alignments-dir "${inputfolder}" --output-dir "${outputfolder}" \
        --cores "${ncores}" --datatype "${datatype}" \
        --use-modeltest --modeltest-criteria "${modeltestcriterion}" --modeltest-perjob-cores "${modeltestperjobcores}" >> "${logfile}" 2>&1
    fi
  elif [ "${astbin}" = 'astral.jar' ] ; then
    if [ "${doboot}" ] ; then
      echo -e "\n## ATPW [$(date "+%F %T")]: Run pargenes with model selection, bootstrap (i=${bootstrapreps}), finish with ASTRAL (${astbin})" 2>&1 | tee -a "${logfile}"
      echo -e "\n## ATPW [$(date "+%F %T")]: Run pargenes with model selection and bootstrap (i=${bootstrapreps})" 2>&1 | tee -a "${logfile}"
      "${PARGENES}" --alignments-dir "${inputfolder}" --output-dir "${outputfolder}" \
        --cores "${ncores}" --datatype "${datatype}" \
        --use-modeltest --modeltest-criteria "${modeltestcriterion}" --modeltest-perjob-cores "${modeltestperjobcores}" \
        --autoMRE -b "${bootstrapreps}" \
        --use-astral >> "${logfile}" 2>&1
    else
      echo -e "\n## ATPW [$(date "+%F %T")]: Run pargenes with model selection, finish with ASTRAL (${astbin})" 2>&1 | tee -a "${logfile}"
      "${PARGENES}" --alignments-dir "${inputfolder}" --output-dir "${outputfolder}" \
        --cores "${ncores}" --datatype "${datatype}" \
        --use-modeltest --modeltest-criteria "${modeltestcriterion}" --modeltest-perjob-cores "${modeltestperjobcores}" \
        --use-astral >> "${logfile}" 2>&1
    fi
  else
    if [ "${doboot}" ] ; then
      echo -e "\n## ATPW [$(date "+%F %T")]: Run pargenes with model selection, bootstrap (i=${bootstrapreps}), finish with ASTER (${astbin})" 2>&1 | tee -a "${logfile}"
      "${PARGENES}" --alignments-dir "${inputfolder}" --output-dir "${outputfolder}" \
        --cores "${ncores}" --datatype "${datatype}" \
        --use-modeltest --modeltest-criteria "${modeltestcriterion}" --modeltest-perjob-cores "${modeltestperjobcores}" \
        --autoMRE -b "${bootstrapreps}" \
        --use-aster --aster-bin "${astbin}" >> "${logfile}" 2>&1
    else
      echo -e "\n## ATPW [$(date "+%F %T")]: Run pargenes with model selection, finish with ASTER (${astbin})" 2>&1 | tee -a "${logfile}"
      "${PARGENES}" --alignments-dir "${inputfolder}" --output-dir "${outputfolder}" \
        --cores "${ncores}" --datatype "${datatype}" \
        --use-modeltest --modeltest-criteria "${modeltestcriterion}" --modeltest-perjob-cores "${modeltestperjobcores}" \
        --use-aster --aster-bin "${astbin}" >> "${logfile}" 2>&1
    fi
  fi
}

count() {
  # Count genes and sequences after each step
  # Input:
  # Output:
  # Call: count
  # TODO: Rewrite to avoid hard codes parts
  echo -e "\n## ATPW [$(date "+%F %T")]: Count sequences in output" | tee -a "${logfile}"
  #nf=N files, ns=N seqs, nt=N taxa
  nf_raw_input='NA' # data
  ns_raw_input='NA' # data
  nt_raw_input='NA' # data
  nf_input='NA' # 1.1_input
  ns_input='NA' # 1.1_input
  nt_input='NA' # 1.1_input
  nf_aligner='NA' # 1.2_mafft
  ns_aligner='NA' # 1.2_mafft
  nt_aligner='NA' # 1.2_mafft
  nf_aligner_alifilter='NA' # 1.3_mafft_bmge
  ns_aligner_alifilter='NA' # 1.3_mafft_bmge
  nt_aligner_alifilter='NA' # 1.3_mafft_bmge
  nf_aligner_alifilter_treeshrink='NA' # 1.4_mafft_bmge_treeshrink
  ns_aligner_alifilter_treeshrink='NA' # 1.4_mafft_bmge_treeshrink
  nt_aligner_alifilter_treeshrink='NA' # 1.4_mafft_bmge_treeshrink
  nf_aligner_treeshrink='NA' # 1.3_mafft_treeshrink
  ns_aligner_treeshrink='NA' # 1.3_mafft_treeshrink
  nt_aligner_treeshrink='NA' # 1.3_mafft_treeshrink
  nf_alifilter='NA' # 1.2_bmge
  ns_alifilter='NA' # 1.2_bmge
  nt_alifilter='NA' # 1.2_bmge
  nf_alifilter_treeshrink='NA' # 1.3_bmge_treeshrink
  ns_alifilter_treeshrink='NA' # 1.3_bmge_treeshrink
  nt_alifilter_treeshrink='NA' # 1.3_bmge_treeshrink
  nf_treeshrink='NA' # 1.2_treeshrink
  ns_treeshrink='NA' # 1.2_treeshrink
  nt_treeshrink='NA' # 1.2_treeshrink
  # Count files and sequences in raw input
  # data -> _raw_input
  nf_raw_input=$(find "${input}" -name '*.fas' | wc -l)
  ns_raw_input=$(grep -c -h '>' "${input}"/*.fas | awk '{sum=sum+$1}END{print sum}')
  nt_raw_input=$(grep -h '>' "${input}"/*.fas | sort -u | wc -l)
  # Go through any potential output folders
  # 1.1_input -> _input
  folder="${runfolder}/1_align/1.1_input"
  if [ -d "${folder}" ] ; then
    nf_input=$(find "${folder}" -name '*.ali' | wc -l)
    ns_input=$(grep -c -h '>' "${folder}"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_input=$(grep -h '>' "${folder}"/*.ali | sort -u | wc -l)
  fi
  # 1.2_mafft -> _aligner
  folder="${runfolder}/1_align/1.2_${aligner}"
  if [ -d "${folder}" ] ; then
    nf_aligner=$(find "${folder}" -name '*.ali' | wc -l)
    ns_aligner=$(grep -c -h '>' "${folder}"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_aligner=$(grep -h '>' "${folder}"/*.ali | sort -u | wc -l)
  fi
  # 1.3_mafft_bmge -> _aligner_bmge
  folder="${runfolder}/1_align/1.3_${aligner}_${alifilter}"
  if [ -d "${folder}" ] ; then
    nf_aligner_alifilter=$(find "${folder}" -name '*.ali' | wc -l)
    ns_aligner_alifilter=$(grep -c -h '>' "${folder}"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_aligner_alifilter=$(grep -h '>' "${folder}"/*.ali | sort -u | wc -l)
  fi
  # 1.4_mafft_bmge_treeshrink -> _aligner_bmge_treeshrink
  folder="${runfolder}/1_align/1.4_${aligner}_${alifilter}_treeshrink"
  if [ -d "${folder}" ] ; then
    nf_aligner_alifilter_treeshrink=$(find "${folder}" -name '*.ali' | wc -l)
    ns_aligner_alifilter_treeshrink=$(grep -c -h '>' "${folder}"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_aligner_alifilter_treeshrink=$(grep -h '>' "${folder}"/*.ali | sort -u | wc -l)
  fi
  # 1.3_mafft_treeshrink -> _aligner_treeshrink
  folder="${runfolder}/1_align/1.4_${aligner}_treeshrink"
  if [ -d "${folder}" ] ; then
    nf_aligner_treeshrink=$(find "${folder}" -name '*.ali' | wc -l)
    ns_aligner_treeshrink=$(grep -c -h '>' "${folder}"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_aligner_treeshrink=$(grep -h '>' "${folder}"/*.ali | sort -u | wc -l)
  fi
  # 1.2_bmge -> _bmge
  folder="${runfolder}/1_align/1.2_${alifilter}"
  if [ -d "${folder}" ] ; then
    nf_alifilter=$(find "${folder}" -name '*.ali' | wc -l)
    ns_alifilter=$(grep -c -h '>' "${folder}"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_alifilter=$(grep -h '>' "${folder}"/*.ali | sort -u | wc -l)
  fi
  # 1.3_bmge_treeshrink -> _bmge_treeshrink
  folder="${runfolder}/1_align/1.3_${alifilter}_treeshrink"
  if [ -d "${folder}" ] ; then
    nf_alifilter_treeshrink=$(find -L "${folder}" -name '*.ali' | wc -l)
    ns_alifilter_treeshrink=$(grep -c -h '>' "${folder}"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_alifilter_treeshrink=$(grep -h '>' "${folder}"/*.ali | sort -u | wc -l)
  fi
  # 1.2_treeshrink -> _treeshrink
  folder="${runfolder}/1_align/1.2_treeshrink"
  if [ -d "${folder}" ] ; then
    nf_treeshrink=$(find "${folder}" -name '*.ali' | wc -l)
    ns_treeshrink=$(grep -c -h '>' "${folder}"/*.ali | awk '{sum=sum+$1}END{print sum}')
    nt_treeshrink=$(grep -h '>' "${folder}"/*.ali | sort -u | wc -l)
  fi
  # Count taxa in astral tree
  if [ "${doaster}" ] ; then
    astraltree=$(find "${runfolder}" -name 'output_species_tree.newick')
    nt_astral=$(sed 's/[(,]/\n/g' "${astraltree}" | grep -c .)
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
  fi
}

cleanUp() {
  ## Compress and remove files in run folder
 local runfolder="$1"
 if [ "${dotreeshrink}" ]; then
   if [ -e  "${runfolder}/tmp_treeshrink/" ] ; then
     rm -rf "${runfolder}/tmp_treeshrink/"
   fi
 fi
 # Compress folders inside pargenes folders
 echo -e "\n## ATPW [$(date "+%F %T")]: Compressing some output" 2>&1 | tee -a "${logfile}"
 cd "${runfolder}" || exit
 mapfile -t arr < <(find 1_align/ -mindepth 1 -maxdepth 1 -type d | sort)
 for d in "${arr[@]::${#arr[@]}-1}" ; do
   e=$(basename "$d")
   f=$(dirname "$d")
   find "${f}" -type d -name "${e}" -execdir tar czf {}.tgz {} ';'
   find "${f}" -type d -name "${e}" -exec rm -r {} '+'
 done
 mapfile -t arr < <(find 2_trees/ -mindepth 1 -maxdepth 1 -type d | sort)
 for d in "${arr[@]::${#arr[@]}-1}" ; do
   e=$(basename "$d")
   f=$(dirname "$d")
   find "${f}" -type d -name "${e}" -execdir tar czf {}.tgz {} ';'
   find "${f}" -type d -name "${e}" -exec rm -r {} '+'
 done
 for d in old_parse_run parse_run supports_run ; do
   find . -type d -name "${d}" -execdir tar czf {}.tgz {} ';'
   find . -type d -name "${d}" -exec rm -r {} '+'
 done
 for d in per_job_logs running_jobs bootstraps concatenated_bootstraps ; do
   find . -type d -name "${d}" -execdir tar czf {}.tgz {} ';'
   find . -type d -name "${d}" -exec rm -r {} '+'
 done
 cd .. || exit
}


createReadme() {
  # Print README.md
  # Input:
  # Output: README.md
  # Call: createReadme
  echo -e "\n## ATPW [$(date "+%F %T")]: Create summary README.md file" | tee -a "${logfile}"
  readme="${runfolder}/README.md"
  outputfolder=$(basename "${runfolder}")
  # Find locations of output
  if [ "${doaster}" ] ; then
    astral_tree_path=$(find "${runfolder}" -type f -name 'output_species_tree.newick')
    gene_trees_path=$(find "${runfolder}" -type f -name 'gene_trees.newick')
  fi
  logfile_path=$(find "${runfolder}" -type f -name 'ATPW.log')
  input_folder_path=$(find "${runfolder}" -type d -name '1.1_input')
  if [ "${doalign}" ] ; then
    aligner_folder_path=$(find "${runfolder}" -type d -name "1.2_${aligner}")
    if [ "${doalifilter}" ] ; then
      aligner_alifilter_folder_path=$(find "${runfolder}" -type d -name "1.3_${aligner}_${alifilter}")
      if [ "${dotreeshrink}" ] ; then
        aligner_alifilter_threeshrink_folder_path=$(find "${runfolder}" -type d -name "1.4_${aligner}_${alifilter}_treeshrink")
        if [ "${doaster}" ] ; then
          steps="${aligner}, ${alifilter}, treeshrink, raxml-ng, ${asterbin}"
        else
          steps="${aligner}, ${alifilter}, treeshrink, raxml-ng"
        fi
      else
        steps="${aligner}, ${alifilter}, raxml-ng, astral"
      fi
    elif [ "${dotreeshrink}" ] ; then
      aligner_threeshrink_folder_path=$(find "${runfolder}" -type d -name "1.3_${aligner}_treeshrink")
      if [ "${doaster}" ] ; then
        steps="${aligner}, treeshrink, raxml-ng, ${asterbin}"
      else
        steps="${aligner}, treeshrink, raxml-ng"
      fi
    else
      if [ "${doaster}" ] ; then
        steps="${aligner}, raxml-ng, ${asterbin}"
      else
        steps="${aligner}, raxml-ng"
      fi
    fi
  else
    if [ "${doalifilter}" ] ; then
      alifilter_folder_path=$(find "${runfolder}" -type d -name "1.2_${alifilter}")
      if [ "${dotreeshrink}" ] ; then
        alifilter_threeshrink_folder_path=$(find "${runfolder}" -type d -name "1.3_${alifilter}_treeshrink")
        if [ "${doaster}" ] ; then
          steps="${alifilter}, treeshrink, raxml-ng, ${asterbin}"
        else
          steps="${alifilter}, treeshrink, raxml-ng"
        fi
      else
        if [ "${doaster}" ] ; then
          steps="${alifilter}, raxml-ng, ${asterbin}"
        else
          steps="${alifilter}, raxml-ng"
        fi
      fi
    else
      if [ "${dotreeshrink}" ] ; then
        threeshrink_folder_path=$(find "${runfolder}" -type d -name '1.2_treeshrink')
        if [ "${doaster}" ] ; then
          steps="treeshrink, raxml-ng, ${asterbin}"
        else
          steps='treeshrink, raxml-ng'
        fi
      else
        if [ "${doaster}" ] ; then
          steps="raxml-ng, ${asterbin}"
        else
          steps='raxml-ng'
        fi
      fi
    fi
  fi

  cat <<- EOF > "${readme}"
# ATPW - Align and Trees in Parallel

## Workflow

- Name: \`$(basename "$0")\`
- Version: ${version}
- Main repository: <https://github.com/nylander/Align-and-trees-parallel-workflow>
- Run started: $start
- Run completed: $(date "+%F %T")
- Steps: ${steps}

## Input data (unfiltered):

\`${input}\`

with ${nf_raw_input} fasta files (${datatype} format).
Total of ${ns_raw_input} sequences from ${nt_raw_input} sequence names.

## Output

### Run folder:

\`${runfolder}\`

### Logfile:

[\`ATPW.log\`](${logfile_path#"$runfolder"/})

EOF

  echo -e "### ML runs per gene:\n" >> "${readme}"
  latest_results_path=$(find "${runfolder}" -type d -name 'mlsearch_run' -exec stat --printf="%Y\t%n\n" {} \; | sort -n -r | head -1 | cut -f2)
  echo -e "[\`mlsearch_run/results/*\`](${latest_results_path#"$runfolder"/}/results/)\n" >> "${readme}"

  if [ "${doaster}" ] ; then
    cat <<- EOF >> "${readme}"
### The ${asterbin} species tree (${nt_astral} terminals):

[\`output_species_tree.newick\`](${astral_tree_path#"$runfolder"/})

### Gene trees file (min Ntax=${minntax}, max Ntax=${maxntax}):

[\`gene_trees.newick\`](${gene_trees_path#"$runfolder"/})

EOF

  fi
  {
  echo -e "### Alignments:\n"
  echo -e "1. [\`1_align/1.1_input/*.ali\`](${input_folder_path#"$runfolder"/})"
  if [ "${doalign}" ] ; then
    echo -e "2. [\`1_align/1.2_${aligner}/*.ali\`](${aligner_folder_path#"$runfolder"/})"
    if [ "${doalifilter}" ] ; then
      echo -e "3. [\`1_align/1.3_${aligner}_${alifilter}/*.ali\`](${aligner_alifilter_folder_path#"$runfolder"/})"
      if [ "${dotreeshrink}" ] ; then
        echo -e "4. [\`1_align/1.4_${aligner}_${alifilter}_treeshrink/*.ali\`](""${aligner_alifilter_threeshrink_folder_path#"$runfolder"/}"")"
      fi
    else
      if [ "${dotreeshrink}" ] ; then
        echo -e "3. [\`1_align/1.3_${aligner}_treeshrink/*.ali\`](""${aligner_threeshrink_folder_path#"$runfolder"/}"")"
      fi
    fi
  else
    if [ "${doalifilter}" ] ; then
      echo -e "2. [\`1_align/1.2_${alifilter}/*.ali\`](""${alifilter_folder_path#"$runfolder"/}"")"
      if [ "${dotreeshrink}" ] ; then
        echo -e "3. [\`1_align/1.3_${alifilter}_treeshrink/*.ali\`](""${alifilter_threeshrink_folder_path#"$runfolder"/}"")"
      fi
    else
      if [ "${dotreeshrink}" ] ; then
        echo -e "2. [\`1_align/1.2_treeshrink/*.ali\`](""${threeshrink_folder_path#"$runfolder"/}"")"
      fi
    fi
  fi
  echo ""
  echo -e "## Filtering summary"
  echo "" >> "${readme}"
  echo -e "| Step | Tool | Nfiles | Nseqs | Ntax |"
  echo -e "| ---  | --- | --- | --- | --- |"
  echo -e "| 0. | Raw input | ${nf_raw_input} | ${ns_raw_input} | ${nt_raw_input} |"
  echo -e "| 1. | Check input | ${nf_input} | ${ns_input} | ${nt_input} |"
  if [ "${doalign}" ] ; then
    echo -e "| 2. | ${aligner} | ${nf_aligner} | ${ns_aligner} | ${nt_aligner} |"
    if [ "${doalifilter}" ] ; then
      echo -e "| 3. | ${alifilter} | ${nf_aligner_alifilter} | ${ns_aligner_alifilter} | ${nt_aligner_alifilter} |"
      if [ "${dotreeshrink}" ] ; then
        echo -e "| 4. | TreeShrink | ${nf_aligner_alifilter_treeshrink} | ${ns_aligner_alifilter_treeshrink} | ${nt_aligner_alifilter_treeshrink} |"
      fi
    else
      if [ "${dotreeshrink}" ] ; then
        echo -e "| 3. | TreeShrink | ${nf_aligner_treeshrink} | ${ns_aligner_treeshrink} | ${nt_aligner_treeshrink} |"
      fi
    fi
  else
    if [ "${doalifilter}" ] ; then
      echo -e "| 2. | ${alifilter} | ${nf_alifilter} | ${ns_alifilter} | ${nt_alifilter} |"
      if [ "${dotreeshrink}" ] ; then
        echo -e "| 3. | TreeShrink | ${nf_alifilter_treeshrink} | ${ns_alifilter_treeshrink} | ${nt_alifilter_treeshrink} |"
      fi
    else
      if [ "${dotreeshrink}" ] ; then
        echo -e "| 2. | TreeShrink | ${nf_treeshrink} | ${ns_treeshrink} | ${nt_treeshrink} |"
      fi
    fi
  fi
  printVersions "${steps}"
  } >> "${readme}"
}

main() {
  # MAIN
  # Align or not, and check alignments
  checkNtaxa "${runfolder}/1_align/1.1_input" "${mintaxfilter}" .ali
  if [ "${doalign}" ] ; then
    align "${runfolder}/1_align/1.1_input" "${runfolder}/1_align/1.2_${aligner}"
    checkAlignments "${runfolder}/1_align/1.2_${aligner}" "${maxinvariantsites}"
  else
    checkAlignments "${runfolder}/1_align/1.1_input" "${maxinvariantsites}"
  fi
  # alifilter or not
  if [ "${doalifilter}" ] ; then
    if [ "${doalign}" ] ; then
      if [ "${dobmge}" ] ; then
        runBmge "${runfolder}/1_align/1.2_${aligner}" "${runfolder}/1_align/1.3_${aligner}_${alifilter}"
      elif [ "${dotrimal}" ] ; then
        runTrimal "${runfolder}/1_align/1.2_${aligner}" "${runfolder}/1_align/1.3_${aligner}_${alifilter}"
      fi
      checkNtaxa "${runfolder}/1_align/1.3_${aligner}_${alifilter}" "${mintaxfilter}" .ali
      checkAlignments "${runfolder}/1_align/1.3_${aligner}_${alifilter}" "${maxinvariantsites}"
    else
      if [ "${dobmge}" ] ; then
        runBmge "${runfolder}/1_align/1.1_input" "${runfolder}/1_align/1.2_${alifilter}"
      elif [ "${dotrimal}" ] ; then
        runTrimal "${runfolder}/1_align/1.1_input" "${runfolder}/1_align/1.2_${alifilter}"
      fi
      checkNtaxa "${runfolder}/1_align/1.2_${alifilter}" "${mintaxfilter}" .ali
      checkAlignments "${runfolder}/1_align/1.2_${alifilter}" "${maxinvariantsites}"
    fi
  fi
  # treeshrink or not
  if [ "${dotreeshrink}" ]; then
    mkdir -p "${runfolder}/tmp_treeshrink"
    # pargenes, fixed model
    if [ "${doalign}" ] ; then
      if [ "${doalifilter}" ] ; then
        pargenesFixedModel "${runfolder}/1_align/1.3_${aligner}_${alifilter}" "${runfolder}/2_trees/2.1_${aligner}_${alifilter}_pargenes"
      else
        pargenesFixedModel "${runfolder}/1_align/1.2_${aligner}" "${runfolder}/2_trees/2.1_${aligner}_pargenes"
      fi
    else
      if [ "${doalifilter}" ] ; then
        pargenesFixedModel "${runfolder}/1_align/1.2_${alifilter}" "${runfolder}/2_trees/2.1_${alifilter}_pargenes"
      else
        pargenesFixedModel "${runfolder}/1_align/1.1_input" "${runfolder}/2_trees/2.1_pargenes"
      fi
    fi
    # setup treeshrink
    if [ "${doalign}" ] ; then
      if [ "${doalifilter}" ] ; then
        setupTreeshrink "${runfolder}/2_trees/2.1_${aligner}_${alifilter}_pargenes/mlsearch_run/results" "${runfolder}/1_align/1.3_${aligner}_${alifilter}" "${runfolder}/tmp_treeshrink"
      else
        setupTreeshrink "${runfolder}/2_trees/2.1_${aligner}_pargenes/mlsearch_run/results" "${runfolder}/1_align/1.2_${aligner}" "${runfolder}/tmp_treeshrink"
      fi
    else
      if [ "${doalifilter}" ] ; then
        setupTreeshrink "${runfolder}/2_trees/2.1_${alifilter}_pargenes/mlsearch_run/results" "${runfolder}/1_align/1.2_${alifilter}" "${runfolder}/tmp_treeshrink"
      else
        setupTreeshrink "${runfolder}/2_trees/2.1_pargenes/mlsearch_run/results" "${runfolder}/1_align/1.1_input" "${runfolder}/tmp_treeshrink"
      fi
    fi
    # treeshrink
    runTreeshrink "${runfolder}/tmp_treeshrink"
    checkNtaxaOutputAli "${runfolder}/tmp_treeshrink" "${mintaxfilter}"
    # realign
    if [ "${doalign}" ] ; then
      if [ "${doalifilter}" ] ; then
        realignerOutputAli "${runfolder}/tmp_treeshrink/" "${runfolder}/1_align/1.4_${aligner}_${alifilter}_treeshrink"
        checkAlignments "${runfolder}/1_align/1.4_${aligner}_${alifilter}_treeshrink" "${maxinvariantsites}"
      else
        realignerOutputAli "${runfolder}/tmp_treeshrink/" "${runfolder}/1_align/1.3_${aligner}_treeshrink"
        checkAlignments "${runfolder}/1_align/1.3_${aligner}_treeshrink" "${maxinvariantsites}"
      fi
    else
      if [ "${doalifilter}" ] ; then
        realignerOutputAli "${runfolder}/tmp_treeshrink/" "${runfolder}/1_align/1.3_${alifilter}_treeshrink"
        checkAlignments "${runfolder}/1_align/1.3_${alifilter}_treeshrink" "${maxinvariantsites}"
      else
        realignerOutputAli "${runfolder}/tmp_treeshrink/" "${runfolder}/1_align/1.2_treeshrink"
        checkAlignments "${runfolder}/1_align/1.2_treeshrink" "${maxinvariantsites}"
      fi
    fi
  fi
  # pargenes, modeltest, (astral)
  if [ "${dotreeshrink}" ]; then
    if [ "${doalign}" ] ; then
      if [ "${doalifilter}" ] ; then
        pargenesModeltestAstral "${runfolder}/1_align/1.4_${aligner}_${alifilter}_treeshrink" "${runfolder}/2_trees/2.2_${aligner}_${alifilter}_treeshrink_pargenes" "${asterbin}"
      else
        pargenesModeltestAstral "${runfolder}/1_align/1.3_${aligner}_treeshrink" "${runfolder}/2_trees/2.2_${aligner}_treeshrink_pargenes" "${asterbin}"
      fi
    else
      if [ "${doalifilter}" ] ; then
        pargenesModeltestAstral "${runfolder}/1_align/1.3_${alifilter}_treeshrink" "${runfolder}/2_trees/2.2_${alifilter}_treeshrink_pargenes" "${asterbin}"
      else
        pargenesModeltestAstral "${runfolder}/1_align/1.2_treeshrink" "${runfolder}/2_trees/2.2_treeshrink_pargenes" "${asterbin}"
      fi
    fi
  else
    if [ "${doalign}" ] ; then
      if [ "${doalifilter}" ] ; then
        pargenesModeltestAstral "${runfolder}/1_align/1.3_${aligner}_${alifilter}" "${runfolder}/2_trees/2.1_${aligner}_${alifilter}_pargenes" "${asterbin}"
      else
        pargenesModeltestAstral "${runfolder}/1_align/1.2_${aligner}" "${runfolder}/2_trees/2.1_${aligner}_pargenes" "${asterbin}"
      fi
    else
      if [ "${doalifilter}" ] ; then
        pargenesModeltestAstral "${runfolder}/1_align/1.2_${alifilter}" "${runfolder}/2_trees/2.1_${alifilter}_pargenes" "${asterbin}"
      else
        pargenesModeltestAstral "${runfolder}/1_align/1.1_input" "${runfolder}/2_trees/2.1_pargenes" "${asterbin}"
      fi
    fi
  fi
}

# Run
main

# Count
count

# Create README.md
createReadme

# Clean up
cleanUp "${runfolder}"

# End
echo -e "\n## ATPW [$(date "+%F %T")]: Reached end of the script\n" 2>&1 | tee -a "${logfile}"
exit 0

