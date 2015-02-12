#!/usr/bin/python

# Name:           split_wigFix.py
# Date Created:   Thu Sep 25 09:27:38 2014
# Date Modified:  Thu Sep 25 09:27:38 2014
# By:             MN Ezewudo
# Description:    Creates individual chromosome wigFix(wiggle format) conservations score files from one wigFix file
#	          of scores for the entire genome.


from string import join
import sys
import gzip

# accept as input, the  name of the condensed gzipped wiggle format file
# and initialize an array of all possible chromosome name for all organisms annotated
# by SeqAnt. Also initialize a tracking array of filehandles to write output files for each 
# of chromosomes

input = sys.argv[1]

# Array of all possible chromosome names
chrs = ["chrM","chr2L","chr2R","chr3L","chr23","chr24","chr25","chr3R", "chrV", "chrVI", "chrVII", "chrVIII", "chrIX", "chrX", "chrXI", "chrXII", "chrXIII", "chrIV", "chrXIV", "chrXV", "chrXVI", "chrY", "chrX", "chrI", "chrII", "chrIII","chrIV","chr1", "chr2", "chr3", "chr4", "chr5", "chr6", "chr7", "chr8", "chr9", "chr10", "chr11","chr12","chr13", "chr14","chr15", "chr16","chr17","chr18","chr19","chr20","chr21","chr22"]

# Array for names of all possible output filehandles
fh =["A","B","C","D","E","f,","g","h","i","J","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","AB","AC", "AD", "AE", "AF","AG", "AH", "AI","AJ","AK","AL","AM","AN","AO","AP","AQ","AR","AS","AT","AU","AV","AX","AY","AW"]

crn = 'chr10'
beac = 0

# open all output files
for j in range(0,len(chrs)): 
    fh[j] = open(chrs[j],'w')

# open and read input file line by line and check for header word fixedstep
# parse for chromosome name on this header line and print output to particular
# chromosome file and continue wrting scores to that file until encounter new header line

fh1 = gzip.open(input,'r')

for line in fh1:
    lines = line.rstrip( "\r\n" )
    if lines.startswith("fixedStep"):
       lined = lines.split(" ")
       chrom = lined[1].split("=")
       if len(chrom[1]) <= 6:
          crn = chrom[1]
          beac = 1
          if crn in chrs:
              print >> fh[chrs.index(crn)], lines
       else:
           beac = 2
    elif beac is 1:
           print >> fh[chrs.index(crn)], lines    
for j in range(0,len(chrs)): 
    fh[j].close
