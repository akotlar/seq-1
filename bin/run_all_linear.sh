#!/bin/sh

./bin/build_genome_assembly.pl --config ./config/hg38_local_no_conserv.yml --location sandbox --type transcript_db &> hg38.transcript_db.log
./bin/build_genome_assembly.pl --config ./config/hg38_local_no_conserv.yml --location sandbox --type snp_db &> hg38.snp_db.log
./bin/build_genome_assembly.pl --config ./config/hg38_local_no_conserv.yml --location sandbox --type gene_db &> hg38.gene_db.log
./bin/build_genome_assembly.pl --config ./config/hg38_local_no_conserv.yml --location sandbox --type genome --hasher ./bin/genome_hasher &> hg38.genome.log
