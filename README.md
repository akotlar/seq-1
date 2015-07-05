Seq
---
---
## How genome assemblies work

- These are specified in a YAML file.
- The assembly has some basic features, e.g., name, description, chromosomes,
and information about the mongo instance for storing some of the track
information.
- There are 2 types of information that an assembly can contain, but the exact
number of either is flexible except for one - all assemblies need a genome
sequence.
	- *sparse tracks* can hold information on genomic site annotation or genomic
	variation.
	- *genome-sized tracks* hold the genomic sequence, various scores, or
	annotations that cover a substantial portion of the genome.

Each genome has features and steps enumerated for creating the needed data to
index and annotate it. Follow the keys and conventions in the example for genome
`hg38` to create a genome / annotation set yourself using the YAML format.

```
---
genome_name: hg38
genome_description: human
genome_chrs:
  - chr1
genome_index_dir: ./hg38/index
host: 127.0.0.1
port: 27107

# sparse tracks
sparse_tracks:
  - type: gene
    local_dir: ./hg38/raw/gene
    local_file: knownGene.txt.gz
    name: knownGene
    sql_statement: SELECT _gene_fields FROM hg38.knownGene LEFT JOIN hg38.kgXref ON hg38.kgXref.kgID = hg38.knownGene.name

# for gene sparse tracks the 'features' key holds extra names the gene may
# be called
    features:
      - mRNA
      - spID
      - spDisplayID
      - geneSymbol
      - refseq
      - protAcc
      - description
      - rfamAcc
  - type: snp
    local_dir: ./hg38/raw/snp/
    local_file: snp141.txt.gz
    name: snp141
    sql_statement: SELECT _snp_fields FROM hg38.snp141

# for snp sparse tracks the 'features' key holds extra annotation
# information
    features:
      - alleles
      - maf
genome_sized_tracks:
  - name: hg38
    type: genome
    local_dir: ./hg38/raw/seq/
    local_files:
      - chr1.fa.gz
    remote_dir: hgdownload.soe.ucsc.edu/goldenPath/hg38/chromosomes/
    remote_files:
      - chr1.fa.gz
  - name: phastCons
    type: score
    local_dir: ./hg38/raw/phastCons
    local_files:
      - phastCons.txt.gz
    remote_dir: hgdownload.soe.ucsc.edu/goldenPath/hg38/phastCons7way/
    remote_files:
      - hg38.phastCons7way.wigFix.gz
    proc_init_cmds:
      - split_wigFix.py _asterisk.wigFix.gz
    proc_chrs_cmds:
      - create_cons.py _chr _dir
      - cat _chr._dir _add_file _dir.txt
      - rm _chr._dir
      - rm _chr
    proc_clean_cmds:
      - gzip phastCons.txt
  - name: phyloP
    type: score
    local_dir: ./hg38/raw/phyloP
    local_files:
      - phyloP.txt.gz
    remote_dir: hgdownload.soe.ucsc.edu/goldenPath/hg38/phyloP7way/
    remote_files:
      - hg38.phyloP7way.wigFix.gz
    proc_init_cmds:
      - split_wigFix.py _asterisk.wigFix.gz
    proc_chrs_cmds:
      - create_cons.py _chr _dir
      - cat _chr._dir _add_file _dir.txt
      - rm _chr._dir
      - rm _chr
    proc_clean_cmds:
      - gzip phyloP.txt
```

# directory structure

The main genome directories are organized like so (and specified in the
configuration file):

		location (-l|--location, passed via command line)
			+-- genome_raw_dir (?needed?)
			+-- genome_index_dir

The `local_dir` (used for the tracks) is stand alone and should be an absolute
path.

# build a complete annotation assembly

We are assuming the data is fetched and in the directories that are specified by
the configuration file.

The following will build all databases sequentially.

		./bin/build_genome_assembly.pl --config ./config/hg38_c_mdb.yml --location /path/to/output --type transcript_db &> hg38.transcript_db.log
		./bin/build_genome_assembly.pl --config ./config/hg38_c_mdb.yml --location /path/to/output --type snp_db &> hg38.snp_db.log
		./bin/build_genome_assembly.pl --config ./config/hg38_c_mdb.yml --location /path/to/output --type gene_db &> hg38.gene_db.log
		./bin/build_genome_assembly.pl --config ./config/hg38_c_mdb.yml --location /path/to/output --type genome --hasher ./bin/genome_hasher &> hg38.genome.log

The following approach will generate shell scripts to allow parallel building.

		# write scripts to build the gene and snp dbs
		./bin/run_all_build.pl -b ./bin/build_genome_assembly.pl -c ./ex/hg38_c_mdb.yml -l /path/to/output

		# build the transcript db
		./bin/build_genome_assembly.pl --config ./config/hg38_c_mdb.yml --location /path/to/output --type transcript_db

		# build conserv score tracks
		./bin/build_genome_assembly.pl --config ./config/hg38_c_mdb.yml --location /path/to/output --type conserv

		# build genome index
		./bin/build_genome_assembly.pl --config ./config/hg38_c_mdb.yml --location /path/to/output --type genome

TODO: add information about how to build CADD scores.

# adding customized Snp Tracks to an assembly

While either the GeneTrack or SnpTrack could be used to add sparse genomic data
to an assembly, it is most straightforward to add sparse data as a SnpTrack. The
procedure is to prepare a tab-delimited file with the desired data that follows
an extended bed file format (described below); define the features you wish
to include as annotations in the configuration file; and, run the builder script
twice - first to create the track data and second to build the binary genome
that is aware of your custom track.

1. prepare a tab-delimited file

The essential columns are: `chrom chromStart chromEnd name`. These are the same
columns as a 4-column bed file. There is no requirement that those columns be in
any particular order or that they are the only columns in the file. The only
essential thing is that they are present and named in the header _exactly_ as
described above. Additional information to be included as part of the annotation
should be in separate labeled columns. You must specify which columns to include
in the genome assembly configuration file and columns that are not specified
will be ignored.

2. add the SnpTrack data to the configuration file. For example,

		- type: snp
			local_dir: /path/to/file
			local_file: hg38.neuro_mutdb.txt
			name: neurodb
			features:
				- name
				- exon_name
				- site
				- ref

The features are names of columns with data to be added to the annotation of the
site. Only columns with this data will be saved, and an error will be generated
if there is no column with a specified name.

3. run the builder script to build the database

You will need to, at least, make the annotation database, and to be safe, you
should remake the encoded binary genome files to update the locations of known
SNPs. The following example supposes that you only have data on chromosome 5 and
that you are adding to an existing assembly.

		# create new database
		build_genome_assembly.pl --config hg38_c_mdb.yml --location /path/to/output --type snp_db --wanted_chr chr5

		# create genome index
		build_genome_assembly.pl --config hg38_c_mdb.yml --location /path/to/output --type genome --verbose --hasher ./bin/genome_hasher

# The following is old and can probably be removed:

## Seq Dependencies

		ack --perl "use " | perl -nlE \
		'{ if ($_ =~ m/\:use ([\w\d.:]+)/) { $modules{$1}++; }}
		END{ print join "\n", sort keys %modules; }' | grep -v Seq

Install dependencies with `cpanm` like so:

		cpanm Carp Cpanel::JSON::XS Cwd DBD::Mock DBI DDP Data::Dump Data::Dumper \
		File::Copy File::Path File::Rsync File::Spec Getopt::Long \
		IO::Compress::Gzip IO::File IO::Socket IO::Socket::INET \
		IO::Uncompress::Gunzip KyotoCabinet Lingua::EN::Inflect List::Util \
		Log::Any::Adapter Modern::Perl Moose Moose::Role
		Moose::Util::TypeConstraints MooseX::Types::Path::Tiny Path::Tiny \
		Pod::Usage Scalar::Util Test::Exception Test::More Time::localtime \
		Try::Tiny Type::Params Types::Standard YAML YAML::XS autodie bigint \
		namespace::autoclean

## setup

1. fetch the data
2. build the database

## some commands

A few snippets to get started

Make some fake test data:

		./bin/make_fake_genome.pl --twoBit_genome ~/lib/hg38.2bit --out test

Build the genome and any extras:

		./bin/build_genome_assembly.pl --config ./config/hg38_local.yml --location sandbox
		./bin/build_genome_assembly_extras.pl --config ./config/hg38_local.yml --location sandbox

Test the build:

		./bin/annotate_ref_site.pl -c ./config/hg38_local.yml --location ./sandbox --chr chr1 --from 200 --to 400

Annotate reference sites or the fake snpfile:

		./bin/read_genome_with_dbs.pl --chr chr1 --from 990 --to 998  --config ./t/hg38_build_test.yml --location ./sandbox/
		./bin/annotate_snpfile.pl --config ./config/hg38_local.yml --snp ./sandbox/hg38/test_files/test.snp.gz --location ./sandbox/ --out test
