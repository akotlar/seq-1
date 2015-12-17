use Benchmark 'timethese';
use strict;
use warnings;
sub eq_alone    { $_[0] eq 'SNP' || $_[0] eq 'INS' || $_[0] eq 'DEL' || $_[0] eq 'MULTIALLELIC'; }
sub regex       { $_[0] =~ /^(SNP|INS|DEL|MULTIALLELIC)/s }
sub indexing {
  index($_[0], 'SNP') > -1 || index($_[0], 'INS') > -1
  || index($_[0], 'DEL') > -1 || index($_[0], 'MULTIALLELIC') > -1
}

timethese (2_000_000, {
  eq_alone => sub { eq_alone('SNP'); eq_alone('SNP'); eq_alone('SNP'); eq_alone('INS'); eq_alone('DEL'); eq_alone('MULTIALLELIC'); },
  regex    => sub { regex('SNP'); regex('SNP'); regex('SNP'); regex('INS'); regex('DEL'); regex('MULTIALLELIC');    },
  index    => sub { 
    indexing('SNP'); indexing('SNP'); 
    indexing('SNP'); indexing('INS'); 
    indexing('DEL'); indexing('MULTIALLELIC');    
  },
  # regex_compiled    => sub { 
  #   regex_compiled('SNP');
  #   regex_compiled('INS'); 
  #   regex_compiled('DEL'); 
  #   regex_compiled('MULTIALLELIC');   
  # },
});

__END__
