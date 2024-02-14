# Arguments for BMGE

- Last modified: tor feb 15, 2024  12:22
- Sign: JN

Note: arguments marked with a star (\*) can be passed to ATPW. Mostly untested, however.

BMGE (version 1.12) arguments:

- `-i <infile>` : input file in fasta or phylip sequential format
- `-t [AA,DNA,CODON]` : sequence coding in the input file (Amino Acid-, DNA-,
  RNA-, or CODON-coding sequences, respectively)
- \*`-m BLOSUM<n>` : for Amino Acid or CODON sequence alignment; name of the
  BLOSUM matrix used to estimate the entropy-like value for each character (n =
  30, 35, 40, ..., 60, 62, 65, ..., 90, 95; default: BLOSUM62)
- \*`-m DNAPAM<n:r>` : for DNA or RNA sequence alignment; name of the PAM
  matrix (n ranges from 1 to 10,000) and transition/transvertion ratio r value
  (r ranges from 0 to 10,000) used to estimate the entropy-like value for each
  character (default: DNAPAM100:2)
- \*`-m DNAPAM<n>` : same as previous option but with r = 1
- \*`-m [ID,PAM0]` : for all sequence coding; identity matrix used to estimate
  entropy- like values for each characters
- \*`-g <rate_max>` : real number corresponding to the maximum gap rate allowed
  per character (ranges from 0 to 1; default: 0.2)
- \*`-g <col_rate:row_rate>` : real numbers corresponding to the maximum gap
  rates allowed per sequence and character, respectively (range from 0 to 1;
  default: 0:0.2)
- \*`-h <thr_max>` : real number corresponding to the maximum entropy threshold
  (ranges from 0 to 1; default: 0.5)
- \*`-h <thr_min:thr_max>` : real numbers corresponding to the minimum and
  maximum entropy threshold, respectively (range from 0 to 1; default: 0:0.5)
- \*`-b <min_size>` : integer number corresponding to the minimum length of
  selected region(s) (ranges from 1 to alignment length; default: 5)
- \*`-w <size>` : sliding window size (must be odd; ranges from 1 to alignment
  length; if set to 1, then entropy-like values are not smoothed; default: 3)
- \*`-s [NO,YES]` : if set to YES, performs a stationarity-based trimming of
  the multiple sequence alignement (default: NO)
- `-o<x> <outfile>` : output file in phylip sequential (`-o, -op, -opp,
  -oppp`), fasta (`-of`), nexus (`-on, -onn, -onnn`) or html (`-oh`) format;
  for phylip and nexus format, options `-opp` and `-onn` allow NCBI-formatted
  sequence names to be renamed onto their taxon name only; options `-oppp` and
  `-onnn` allow renaming onto `'taxon name'_____'accession number'` (default:
  `-oppp`)
- `-c<x> <outfile>` : same as previous option but for the complementary
  alignment, except for html output (i.e. `-ch` do not exist)
- `-o<y> <outfile>` : converts the trimmed alignment in Amino Acid- (-oaa),
  DNA- (-odna), codon- (-oco) or RY- (-ory) coding sequences (can be combined
  with -o<x> options; default: no conversion) (see documentation for more
  details and more output options)

