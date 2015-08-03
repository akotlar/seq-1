# Seq ToDo

1. Ensure c programs are compiled when package is installed.
2. include instructions about getting kch
3. build additional genomes (finish mm10)
4. add this to testing
  - ideally build a mini genome as part of the build process
  - select a small gene track like CCDS or refGene
5. for conservation tracks - check the needed files are present before 
  the build starts (i.e., command is submitted).
6. the `--force` option is being used for different things and might 
  need to be divided into other options
    - skip unknown chromosomes
    - skip sites where the reference base and the base in the db disagree
    - overwrite the annotation file (only in the `annotate_snpfile.pl`
    - overwrite the build files (i.e., the KCH files, etc.)

