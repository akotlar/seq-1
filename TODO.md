# Seq ToDo

1. attribute `snp_id` to the appropriate db it came from - e.g., clinvar
   versus snp141.
2. ensure phastcons and phylop are created and read in the same way - round
   trip integrity.
3. more tests
4. build non-human assemblies
5. integrate statistics calculators
6. integrate cadd scores for hg38 and hg19

# bugs

1. add ucsc kgID to names, associate that transcript with the particular error
    message that a transcript doesn't end with a stop codion, etc
    e.g., uc021tyx.1 chr17 + transcript does not end with stop codon (this is
      on of the several varieties of MAPT and the only one that doesn't end
      with a stop)
