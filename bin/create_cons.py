#!/usr/bin/python
# Name:           create_cons.py
# Date Created:   Thu Sep 25 09:27:38 2014
# Date Modified:  Thu Sep 25 09:27:38 2014
# By:             MN Ezewudo
# Description:    Accepts wigfix type file with conservation scores for any given genome
#                 and creates a SeqAnt readable conservation score file with three columnns:
#		  the chromosome name, the base position and the actual conservation score

import sys

#initialize values for base position and offset steps in input file
posit = 0
step = 0
input1 = sys.argv[1]
input2 = sys.argv[2]

#create filehandles for the input and output files
#
fh1 = open(input1, 'r')
fh2 = open(input1 + "." + input2, 'w')

#open the input file, read through line by line
#and for each line check for header word "fixedstep" and parse for
#both the current base position and offset count and print required position and score
#to output file and increase the offset and position values respectively.

for line in fh1:
    lined = line.rstrip( "\r\n" )
    if lined.startswith("fixedStep"):
       S1 = lined.split(" ")
       pos = S1[2].split("=")
       posit = int(pos[1])
       stepped = S1[3].split("=")
       step = int(stepped[1])
    else:
       print >> fh2, input1 + "\t" +str(posit) + "\t" + lined
    
    posit += step
fh1.close()
