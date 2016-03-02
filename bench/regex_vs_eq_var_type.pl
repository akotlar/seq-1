use Benchmark 'timethese';
use strict;
use warnings;
sub eq_alone    { if($_[0] eq 'SNP' || $_[0] eq 'INS' || $_[0] eq 'DEL' || $_[0] eq 'MULTIALLELIC'){return 1} return 0; }
sub regex       { if($_[0] =~ /(SNP|INS|DEL|MULTIALLELIC)$/s){return 1;} return 0; }

my $foundVarType;
sub indexing {
  if(index($_[0], 'SNP') > -1){
      $foundVarType = 'SNP';
    } elsif(index($_[0], 'DEL') > -1) {
      $foundVarType = 'DEL';
    } elsif(index($_[0], 'INS') > -1) {
      $foundVarType = 'INS';
    } elsif(index($_[0], 'MULTIALLELIC') > -1) {
      $foundVarType = 'MULTIALLELIC';
    } else {
      $foundVarType = '';
    }
    return $foundVarType;
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
