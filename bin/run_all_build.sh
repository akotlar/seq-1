#!/bin/sh

./bin/build_genome_assembly.pl --config ./config/hg38_local.yml --location sandbox --type conserv --scorer ./bin/genome_scorer &> hg38.conserv.log &
./bin/build_genome_assembly.pl --config ./config/hg38_local.yml --location sandbox --type transcript_db &> hg38.transcript_db.log  &
./bin/build_genome_assembly.pl --config ./config/hg38_local.yml --location sandbox --type snp_db &> hg38.snp_db.log &
./bin/build_genome_assembly.pl --config ./config/hg38_local.yml --location sandbox --type gene_db &> hg38.gene_db.log 
./bin/build_genome_assembly.pl --config ./config/hg38_local.yml --location sandbox --type genome --hasher ./bin/genome_hasher &> hg38.genome.log 
