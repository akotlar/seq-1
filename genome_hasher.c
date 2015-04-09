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
 * Place, Suite 330, Boston, MA  02111-1307  USA */

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

#define MAX_FILE_BUFFER 1200000000

int
main(int argc, char *argv[])
{
	FILE           *filelist;
	FILE           *thisfile;
	FILE           *outfile;
	gzFile		reffile;
	char		ss        [4096], sss[4096], char_mask[256];
	long		i;

	if (argc != 4) {
		printf("\n Usage %s genome_file annotation_file_list outfile\n", argv[0]);
		exit(1);
	}
	sprintf(ss, "%s", argv[3]);
	if ((outfile = fopen(ss, "w")) == (FILE *) NULL) {
		printf("\n Can not open file %s\n", ss);
		exit(1);
	}
	long		genome_size = (long)3500000000;
	char           *genome_buffer;

	genome_buffer = (char *)malloc(sizeof(char) * (genome_size + 1));
	if (!genome_buffer) {
		printf("\n Failed to allocate memory for the Genome Buffer \n");
		exit(1);
	}
	if ((reffile = gzopen(argv[1], "r")) == (gzFile) NULL) {
		printf("\n Can not open file %s for reading\n", sss);
		exit(1);
	}
	printf("\n About to read genome \n\n");

	long		g_temp = 0;
	if (genome_size < MAX_FILE_BUFFER)
		g_temp = gzread(reffile, (void *)genome_buffer, (unsigned int)sizeof(char) * genome_size);
	else {
		long		count = 0;
		while (count < genome_size) {
			int		ttemp = minim((long)genome_size - count, MAX_FILE_BUFFER);
			g_temp += gzread(reffile, (void *)&genome_buffer[count], ttemp);
			count += ttemp;
		}
	}
	gzclose(reffile);
	genome_size = g_temp;
	printf("\n Genome Size is %ld \n", genome_size);

  // N = 4 for encoding purposes; here we set all characters to give the N value
	for (i = 0; i < 256; i++)
		char_mask[i] = 4;

  // Now, we set a few specific characters to values that are meaningful to us
  // and this also takes care of the uc vs. lc issue
	char_mask['A'] = 0;
	char_mask['a'] = 0;
	char_mask['C'] = 1;
	char_mask['c'] = 1;
	char_mask['G'] = 2;
	char_mask['g'] = 2;
	char_mask['T'] = 3;
	char_mask['t'] = 3;

  // now actually encode the genome into char's
	for (i = 0; i < genome_size; i++)
		genome_buffer[i] = char_mask[(int)genome_buffer[i]];

  // open our file with the list of files
	if ((filelist = fopen(argv[2], "r")) == (FILE *) NULL) {
		printf("\n Can't open %s for reading \n", argv[2]);
		exit(1);
	}
	fgets(sss, 4095, filelist);
	int len = strlen(sss);

  // keep reading unless we hit a blank line
	while (len > 2) {
		char   *token;
		token = strtok(sss, " \n\t");

    // open the file with what we want to add
		if ((thisfile = fopen(token, "r")) == (FILE *) NULL) {
			printf("\n Can't open %s for reading \n", token);
			exit(1);
		}
		fgets(sss, 4095, thisfile);

    // read the first line of the file, this tells us what we're adding
		int		this_add = atoi(sss);
		if ((this_add < 1) || (this_add > 255)) {
			printf("\n Found a mask of %d which is impossible [1...255 is possible range] \n", this_add);
			exit(2);
		}

		fgets(sss, 4095, thisfile);
		int len2 = strlen(sss);

		long genome_size = (long)3500000000;
		char *genome_buffer;

		this_buffer = (char *)malloc(sizeof(char) * (genome_size + 1));
		if (!this_buffer) {
			printf("\n Failed to allocate memory for temp genome buffer \n");
			exit(1);
		}

    // now read the file - format: Start\tStop\n
		while (len2 > 2) {
			char *token2;
			long  site;
			token2 = strtok(sss, " \n\t");
			site = atol(token2);

			// sanity check
			if ((site < 0) || (site > genome_size)) {
				printf("\n Found a start position of %ld in a genome of size %ld \n", start, genome_size);
				exit(3);
			}

			// save the site in 'this_buffer'
			this_buffer[site] = 1;

			sss[0] = '\0';
			if (!feof(thisfile))
				fgets(sss, 4095, thisfile);
			len2 = strlen(sss);
		}

		// add sites that are present in 'this_buffer'
		for (int i = 0; i <= genome_size; i++)
			if (this_buffer[i] == 1 )
				genome_buffer[i] += this_add;

		free(this_buffer);
		fclose(thisfile);
		sss[0] = '\0';

    // read the next line of the file list if we haven't hit the end
		if (!feof(filelist))
			fgets(sss, 4095, filelist);
		len = strlen(sss);
	}

	fwrite(genome_buffer, sizeof(char), genome_size, outfile);

	fclose(outfile);
	return 0;

}
