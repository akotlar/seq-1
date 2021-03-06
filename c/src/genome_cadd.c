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
 * Name: genome_cadd.c
 * Compile: gcc -Wall -Wextra -O3 -lm -lz genome_cadd.c -o ./bin/genome_cadd
 * Description: Encodes 3 genome strings using a "Cadd" formatted file
 *  Input: genome_file => a "Cadd" formatted file, basically a bed file with
 *                        three extra columns representing the CADD scores in
 *                        alphabetical order
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

#define minim(a,b) ((a<b)?a:b)
#define maxim(a,b) ((a>b)?a:b)

typedef struct chrom_node
{
  char name[256];
  long offset;
} CHROM_NODE;
int compare_node(const void *a,const void *b);
int b_comp(const void *a,const void *b);
CHROM_NODE * my_node_search(char *ss,CHROM_NODE **list,int count);

int main(int argc, char *argv[])
{
  FILE *chrfile;
  FILE *outfile;
  gzFile wigfixfile;
  char ss[4096],sss[4096];
  int R,j;
  double xmax,xmin;
  long i;
  CHROM_NODE **clist;

  if(argc != 8)
  {
    printf("\n Usage %s genome_size offset_file Cadd_scoresfile Max Min R outfile\n",argv[0]);
    exit(1);
  }

  long genome_size = (long)atol(argv[1]);
  char **genome_buffer;

  genome_buffer = (char **)malloc(sizeof(char *)*(3));
  if(!genome_buffer)
  {
    printf("\n Failed to allocate memory for the Genome Buffer \n");
    exit(1);
  }
  for(j=0;j<3;j++)
  {
    genome_buffer[j] = (char *)malloc(sizeof(char)*(genome_size+1));
    if(!genome_buffer[j])
    {
      printf("\n Failed to allocate memory for the Genome Buffer \n");
      exit(1);
    }
  }
  clist = (CHROM_NODE**)malloc(sizeof(CHROM_NODE *)*1000);
  if(!clist)
  {
    printf("\n Failed to allocate memory for the Chromosome list \n");
    exit(1);
  }
  if((chrfile = fopen(argv[2],"r")) == (FILE *)NULL)
  {
    printf("\n Can't open %s which should be the chromsome offset file for reading \n",argv[2]);
    exit(1);
  }
  xmax = (double)atof(argv[4]);
  xmin = (double)atof(argv[5]);
  if(xmin >= xmax)
  {
    printf("\n Impossible max = %g  min = %g \n",xmax,xmin);
    exit(1);
  }
  R = atoi(argv[6]);
  if( (R < 5) || (R > 255) )
  {
    printf("\n Impossible R [8..255] = %d \n",R);
    exit(1);
  }

  if((wigfixfile=gzopen(argv[3],"r"))==(gzFile)NULL)
  {
    printf("\n Can not open file %s which should be the CADD file for reading\n",sss);
    exit(1);
  }

  printf("\n Genome Size is %ld \n",genome_size);
  for(i=0;i<genome_size;i++)
    for(j=0;j<3;j++)
      genome_buffer[j][i] = (char)0;

  fgets(sss,4095,chrfile);
  fgets(sss,4095,chrfile);
  int len = strlen(sss);
  j = 0;

  while(len > 2)
  {
    clist[j] = (CHROM_NODE *)malloc(sizeof(CHROM_NODE));
    clist[j]->name[0] = '\0';
    clist[j]->offset = (long)0;
    char *token;
    token = strtok(sss,": \n\t");
    strcpy(clist[j]->name,token);
    token = strtok(NULL,": \n\n");
    clist[j]->offset = atol(token);
    printf("\n Just stored %s with offset %ld at memory pos = %ld\n",clist[j]->name,clist[j]->offset,(long)clist[j]);
    sss[0] = '\0';
    if(!feof(chrfile))
      fgets(sss,4095,chrfile);
    len = strlen(sss);
    j++;
  }
  fclose(chrfile);

  int no_chrom = j;
  printf("\n There are %d chromosomes in the genome \n\n",no_chrom);
  qsort(clist,no_chrom,sizeof(CHROM_NODE *),compare_node);
  printf("\n Finished sorting chromosome list \n\n");
  int skip_it = 1;
  gzgets(wigfixfile,sss,4095);
  len = strlen(sss);
  char last_chrom[1024];
  strcpy(last_chrom,"!!!!");
  long current_pos = 0;
  double this_x;
  double this_y;
  double beta = (double)(R-1) / (xmax - xmin);
  CHROM_NODE *last_cn = NULL;
  while(len > 8)
  {
    char *token;
    token = strtok(sss," \n\t");
    if(strcmp(token,last_chrom) != 0)
    {
      // last_cn = ((CHROM_NODE *) bsearch(token,clist,no_chrom,sizeof(CHROM_NODE *),b_comp));
      last_cn = my_node_search(token,clist,no_chrom);
      if(last_cn)
      {
        printf("\n Found %s which is at memory position %ld has name %s and offset %ld\n",token,(long)last_cn,last_cn->name,last_cn->offset);
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
      token = strtok(NULL," \n\t");
      current_pos += atol(token);
      for(j=0;j<3;j++)
      {
        token = strtok(NULL," \n\t");
        this_x = (double)atof(token);
        if( (this_x > xmax) || (this_x < xmin) || (current_pos < 0) || (current_pos > genome_size))
        {
          printf("\n Impossible %s position %ld which is %g \n",last_cn->name,current_pos-(last_cn->offset-1),this_x);
          exit(2);
        }
        this_y = 1 + (int)floor((double)beta*(this_x - xmin));
        // printf("\n %ld %d %g %c",current_pos,j,this_x,(char)this_y);
        genome_buffer[j][current_pos] = (char)this_y;
      }
    }
    sss[0] = '\0';
    if(!gzeof(wigfixfile))
     gzgets(wigfixfile,sss,4095);
    len = strlen(sss);
  }
  printf("\n About to write everything \n\n");

  for(j=0;j<3;j++)
  {
   sprintf(ss,"%s.%d",argv[7],j);
    if((outfile=fopen(ss,"w"))==(FILE *)NULL)
    {
      printf("\n Can not open file %s\n",ss);
      exit(1);
    }
    fwrite(genome_buffer[j],sizeof(char),genome_size,outfile);
    fclose(outfile);
  }
  return 0;
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
  return strcmp(aa,bb->name);
}
