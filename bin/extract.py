#!/usr/bin/python

# Name:           extract.py
# Date Created:   Thu Sep 25 09:27:38 2014
# Date Modified:  Thu Sep 25 09:27:38 2014
# By:             MN Ezewudo
# Description:    Splits a multi-fasta format genome sequence to individual chromosome sequence files
#                 Accepts the name of respective chromosome searches for chromosome in the multifasta file
#                 and extracts sequences the chromosome sequence into a new file


import sys
import gzip

# create filehandles for input gzipped multifasta file and output chromosome file
inp0 = sys.argv[2]
inp1 = sys.argv[1]
inp2 = inp1 + '.fa'

# initialize counter for presence of chromosome name in mutli-fasta file
# and open bot input and output files
inseq = 0
fh1 = gzip.open(inp0, 'r')
fh2 = open(inp2,'w')

# read through input file line by line
# find headers and parse for chromosome name
# and print sequences if chromosome is present
for line in fh1:
    lined = line.rstrip( "\r\n" )
    if inseq is 1:
       if lined.startswith('>'):
          inseq = 0
       else:
          print >> fh2, lined
    if lined.startswith('>') and lined.find(inp1) != -1:
       inseq = 1
       print >> fh2, lined
fh1.close()
fh2.close()
