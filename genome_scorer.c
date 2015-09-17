/*
 * The code itself is Copyright (C) 2015, by David J. Cutler.
 *
 * This library is free software; you can redistribute it and/or modify it under
 * the terms of the GNU Lesser General Public License as published by the
 * Free Software Foundation; either version 2.1 of the License, or (at your
 * option) any later version. This library is distributed in the hope that it
 * will be useful, but WITHOUT ANY WARRANTY; without even the implied
 * warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details. You should have
 * received a copy of the GNU Lesser General Public License along with this
 * library; if not, write to the Free Software Foundation, Inc., 59 Temple
 * Place, Suite 330, Boston, MA  02111-1307  USA
 *
 * Name: genome_scorer.c
 * Compile: gcc -Wall -Wextra -O3 -lm -lz argtable3.c genome_scorer.c -o ./bin/genome_scorer
 * Description: Encodes a genome using a user specified scheme
 *  Input:  genomeSize offset_file (YAML) wigFix_file Max Min R outputfile
 *            Max and Min are the range of the scores
 *            R is the scaler
 *  Output: genome-sized string of encoded char's
 * Authors: David Cutler and Thomas Wingo
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <float.h>
#include <ctype.h>
#include <zlib.h>
#include <time.h>
#include <dirent.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include "argtable3.h"
#include "dbg.h"

#define minim(a,b) ((a<b)?a:b)
#define maxim(a,b) ((a>b)?a:b)

struct arg_lit *help;
struct arg_str *argGenomeSize;
struct arg_int *argR;
struct arg_dbl *argMax, *argMin;
struct arg_file *argChrFile, *argOutFile, *argWigFixFile;
struct arg_end *end;

typedef struct chrom_node
{
  char name[256];
  long offset;
} CHROM_NODE;

int compare_node(const void *a,const void *b)
{
  CHROM_NODE *aa,*bb;
  aa = (CHROM_NODE*)(*(CHROM_NODE**)a);
  bb = (CHROM_NODE*)(*(CHROM_NODE**)b);
  return strcmp(aa->name,bb->name);
}

int b_comp(const void *a,const void *b)
{
  CHROM_NODE *bb;
  char *aa;
  aa = (char *)(a);
  bb = (CHROM_NODE*)(*(CHROM_NODE**)b);
  // printf("\n offset for this %s is %lu \n", bb->name, bb->offset);
  return strcmp(aa,bb->name);
}

CHROM_NODE * my_node_search(char *ss,CHROM_NODE **list,int count)
{
  if(count <= 0)
    return NULL;

  int i = count/2;
  int j = b_comp(ss,&(list[i]));

  if(j == 0)
    return list[i];
  if(j < 0)
    return  my_node_search(ss,list,i);

  return my_node_search(ss,&(list[i+1]),count-(i+1));
}

int genomeScorer( 
    long genomeSize, int R, double min, double max, 
    const char *outFile, 
    const char *chrFile, 
    const char **wigFixFile, int nWigFixFile )
{
  FILE *chrFh, *outFh;
  char sss[4096];
  long i;
  CHROM_NODE **clist;

  check( (min < max), "Impossible max = %g  min = %g.", max, min );
  check( ((R > 5) && (R < 255)), "Impossible R [8..255] = %d.",R);
  check( ((outFh=fopen(outFile, "w"))!=(FILE *)NULL), "Cannot write output to '%s'.", outFile );

  char *genome_buffer = (char *)malloc(sizeof(char)*(genomeSize+1));
  check_mem(genome_buffer);
  
  clist = (CHROM_NODE**)malloc(sizeof(CHROM_NODE *)*1000);
  check_mem(clist);

  log_info("Genome Size is %ld", genomeSize);

  // zero out genome array
  for(i=0;i<genomeSize;i++)
    genome_buffer[i] = (char)0;

  // read chromosome offset file
  check( ((chrFh=fopen(chrFile, "r"))!=(FILE *)NULL), "Cannot open chromosome offset file '%s' for reading.", chrFile );
  fgets(sss,4095,chrFh);
  fgets(sss,4095,chrFh);
  int len = strlen(sss);
  int nChrom = 0;

  while(len > 2)
  {
    clist[nChrom] = (CHROM_NODE *)malloc(sizeof(CHROM_NODE));
    clist[nChrom]->name[0] = '\0';
    clist[nChrom]->offset = (long)0;
    char *token;
    token = strtok(sss,": \n\t");
    strcpy(clist[nChrom]->name,token);
    token = strtok(NULL,": \n\n");
    clist[nChrom]->offset = atol(token);
    log_info("Just stored %s with offset %ld.",clist[nChrom]->name,clist[nChrom]->offset);
    sss[0] = '\0';
    if(!feof(chrFh))
    fgets(sss,4095,chrFh);
    len = strlen(sss);
    nChrom++;
  }
  fclose(chrFh);

  log_info("There are %d chromosomes in the genome.", nChrom);
  qsort(clist,nChrom,sizeof(CHROM_NODE *),compare_node);
  log_info("Finished sorting chromosome list.");

  // read the wig fix files 
  for (int i = 0; i < nWigFixFile; i++)
  {
    gzFile wigFixFh;
    int skip_it = 1;
    check( (wigFixFh = gzopen( wigFixFile[i], "r" ) )!=(gzFile)NULL, "Cannot open wigfix file '%s'.", wigFixFile[i] );
    gzgets(wigFixFh,sss,4095);
    len = strlen(sss);
    int step = 1;
    char last_chrom[1024];
    strcpy(last_chrom,"!!!!");
    long current_pos = 0;
    double this_x;
    double this_y;
    double beta = (double)(R-1) / (max - min);
    CHROM_NODE *last_cn = NULL;
  
    while(len > 2)
    {
      if(sss[0] == 'f')
      {
        char *token;
        token = strtok(sss," \n\t=");
        token = strtok(NULL," \n\t=");
        token = strtok(NULL," \n\t=");
        if(strcmp(token,last_chrom) != 0)
        {
          // last_cn = (CHROM_NODE *) bsearch(token,clist,no_chrom,sizeof(CHROM_NODE *),b_comp);
          last_cn = my_node_search(token,clist,nChrom);
          if(last_cn)
          {
            // printf("\n Found %s which is at memory position %ld has name %s and offset %ld\n",
            //   token, (long)last_cn, last_cn->name, last_cn->offset);
            skip_it = 0;
          }
          else
          {
            printf("\n Skipping %s \n",token);
            skip_it = 1;
          } 
          strcpy(last_chrom,token);
        }
  
        if(!skip_it)
        {
          current_pos = last_cn->offset-1;
          // printf("\n New offset: %ld \n", current_pos );
          token = strtok(NULL," \n\t=");
          token = strtok(NULL," \n\t=");
          // printf("\n New offset: %s \n", token );
          current_pos += atol(token);
          token = strtok(NULL," \n\t=");
          token = strtok(NULL," \n\t=");
          step = atoi(token);
        }
      }
      else
      {
    	  if(!skip_it)
      	{
          this_x = (double)atof(sss);
          if( (this_x > max) || (this_x < min) )
          {
            printf("\n Impossible X value encountered at position %ld which is %g \n",current_pos,this_x);
            exit(2);
          }
          this_y = 1 + floor((double)beta*(this_x - min));
          int j;
          for(j = 0;j<step;j++)
            genome_buffer[current_pos++] = (char)this_y;
        }
      }
    sss[0] = '\0';
    if(!gzeof(wigFixFh))
      gzgets(wigFixFh,sss,4095);
    len = strlen(sss);
    }
  }

  // write final encoded file
  fwrite(genome_buffer,sizeof(char),genomeSize,outFh);
  fclose(outFh);
  return 0;

error:
  return 1;
}

int main( int argc, char *argv[] )
{
  void *argtable[] = {
    help          = arg_litn(NULL, "help", 0, 1, "display this help and exit"),
    argGenomeSize = arg_strn("g", "genomeSize", "<num>", 1, 1, "size of genome"),
    argR          = arg_intn("r", "R", "<num>", 1, 1, "value of R"),
    argChrFile    = arg_filen("c", "chr", "<file>", 1, 1, "chromosome offset file"),
    argWigFixFile = arg_filen("w", "wig", "<file>", 1, 100, "wig fix file"),
    argOutFile    = arg_filen("o", "out", "<file>", 1, 1, "output file"),
    argMax        = arg_dbln(NULL, "max", "<num>", 1, 1, "maximum value"),
    argMin        = arg_dbln(NULL, "min", "<num>", 1, 1, "minimum value"),
    end           = arg_end(20),
  };

  int exitcode = 0;
  char progName[] = "genome_scorer";
  int nerrors = arg_parse(argc, argv, argtable);

  if (help->count > 0) {
    printf("Usage: %s", progName);
    arg_print_syntax( stdout, argtable, "\n");
    arg_print_glossary(stdout, argtable, " %-25s %s\n");
    exitcode = 0;
    goto exit;
  }

  if (nerrors > 0)
  {
    arg_print_errors(stdout, end, progName);
    printf("Try '%s --help' for further information.\n", progName);
    exitcode = 1;
    goto exit;
  }

  if (nerrors == 0)
  {
    long genomeSize = (long)atol(argGenomeSize->sval[0]);

    exitcode = genomeScorer( genomeSize, argR->ival[0], argMin->dval[0], argMax->dval[0], 
        argOutFile->filename[0], argChrFile->filename[0], argWigFixFile->filename, 
        argWigFixFile->count );
    goto exit;
  }

exit:
  arg_freetable(argtable, sizeof(argtable) / sizeof(argtable[0]));
  return exitcode;
}


