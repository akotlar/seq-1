Seq
---
---

# setup

1. fetch the data
2. build the database

# some commands

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
index and annotate it.
Follow the keys and conventions in the example for genome `hg38` to create a genome / annotation set yourself using the YAML format.

```
---
genome_name: hg38
genome_description: human
genome_chrs:
  - chr1
genome_db_dir: sandbox
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
