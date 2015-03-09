#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;
use File::Copy;
use Scalar::Util qw( blessed );
use DDP;
use Lingua::EN::Inflect qw( A PL_N );

plan tests => 60;

my $package = "Seq::Config::GenomeSizedTrack";

# load package
use_ok($package) || die "$package cannot be loaded";

# check is moose object
check_isa( $package, ['Moose::Object'] );

# check package uses Moose
ok( $package->can('meta'), "$package has a meta() method" )
  or BAIL_OUT("$package does not have a meta() method.");

# check read-only attribute have read but no write methods
has_ro_attr ( $package, $_ ) for ( qw ( name type genome_chrs local_dir 
  local_files remote_dir remote_files proc_init_cmds proc_chrs_cmds 
  proc_clean_cmds ) );

# check type constraints - Str
for my $attr_name (qw( name local_dir remote_dir ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'Str', "$attr_name type is Str" );
}

# check type constraints - ArrayRef[Str]
for my $attr_name ( qw( genome_chrs local_files remote_files proc_init_cmds proc_chrs_cmds 
  proc_clean_cmds ) )
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'ArrayRef[Str]', "$attr_name type is ArrayRef[Str]" );
}

# check type constraints - GenomeSizedTrackType
for my $attr_name ( qw( type ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'GenomeSizedTrackType', "$attr_name type is GenomeSizedTrackType" );
}

# check methods 
#   1 - index coding:   get_idx_code
#   2 - index decoding: get_idx_base, get_idx_in_gan, get_idx_in_gene, get_idx_in_exon, 
#                       get_idx_in_snp
{
  my (%idx_codes, %idx_base, %idx_in_gan, %idx_in_gene, %idx_in_exon, %idx_in_snp);
  my @bases      = qw( A C G T N );
  my @annotation = qw( 0 1 );
  my @in_exon    = qw( 0 1 );
  my @in_gene    = qw( 0 1 );
  my @in_snp     = qw( 0 1 );
  my @char       = ( 0 .. 255 );
  my $i          = 0;

  my (@exp_idx_code, @obs_idx_code);

  foreach my $base (@bases)
  {
    foreach my $gan (@annotation)
    {
      foreach my $gene (@in_gene)
      {
        foreach my $exon (@in_exon)
        {
          foreach my $snp (@in_snp)
          {
            my $code = $char[$i];
            $i++;
            push @exp_idx_code, $code;
            push @obs_idx_code, $package->get_idx_code( $base, $gan, $gene, $exon, $snp );
            $idx_codes{$base}{$gan}{$gene}{$exon}{$snp} = $code;

            $idx_base{$code}    = $base;
            $idx_in_gan{$code}  = $base if $gan;
            $idx_in_gene{$code} = $base if $gene;
            $idx_in_exon{$code} = $base if $exon;
            $idx_in_snp{$code}  = $base if $snp;
          }
        }
      }
    }
  }
  # check build idx codes
  is_deeply(\@exp_idx_code, \@obs_idx_code, 'got idx correct index codes');

  # check decoding of idx bases
  my @exp_bases = map { $idx_base{ $_ } } sort keys %idx_base;
  my @obs_bases = map { $package->get_idx_base( $_ ) } sort keys %idx_base;
  is_deeply( \@exp_bases, \@obs_bases, 'decoded bases correctly');

  # check decoding of idx in_gan
  @exp_bases = map { $idx_in_gan{ $_ } } sort keys %idx_in_gan;
  @obs_bases = map { $package->get_idx_in_gan( $_ ) } sort keys %idx_in_gan;
  is_deeply( \@exp_bases, \@obs_bases, 'decoded in gene annotation code correctly');

  # check decoding of idx in_gan
  @exp_bases = map { $idx_in_gene{ $_ } } sort keys %idx_in_gene;
  @obs_bases = map { $package->get_idx_in_gene( $_ ) } sort keys %idx_in_gene;
  is_deeply( \@exp_bases, \@obs_bases, 'decoded in gene code correctly');

  # check decoding of idx exon
  @exp_bases = map { $idx_in_exon{ $_ } } sort keys %idx_in_exon;
  @obs_bases = map { $package->get_idx_in_exon( $_ ) } sort keys %idx_in_exon;
  is_deeply( \@exp_bases, \@obs_bases, 'decoded in exon code correctly');

  # check decoding of idx snp
  @exp_bases = map { $idx_in_snp{ $_ } } sort keys %idx_in_snp;
  @obs_bases = map { $package->get_idx_in_snp( $_ ) } sort keys %idx_in_snp;
  is_deeply( \@exp_bases, \@obs_bases, 'decoded in gene code correctly');
}


sub check_isa {
    my $class   = shift;
    my $parents = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my @isa = $class->meta->linearized_isa;
    shift @isa;    # returns $class as the first entry

    my $count = scalar @{$parents};
    my $noun = PL_N( 'parent', $count );

    is( scalar @isa, $count, "$class has $count $noun" );

    for ( my $i = 0; $i < @{$parents}; $i++ ) {
        is( $isa[$i], $parents->[$i], "parent[$i] is $parents->[$i]" );
    }
}

sub has_ro_attr {
    my $class = shift;
    my $name  = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $articled = A($name);
    ok(
        $class->meta->has_attribute($name),
        "$class has $articled attribute"
    );

    my $attr = $class->meta->get_attribute($name);

    is(
        $attr->get_read_method, $name,
        "$name attribute has a reader accessor - $name()"
    );
    is(
        $attr->get_write_method, undef,
        "$name attribute does not have a writer"
    );
}

sub has_rw_attr {
    my $class      = shift;
    my $name       = shift;
    my $overridden = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $articled = $overridden ? "an overridden $name" : A($name);
    ok(
        $class->meta->has_attribute($name),
        "$class has $articled attribute"
    );

    my $attr = $class->meta->get_attribute($name);

    is(
        $attr->get_read_method, $name,
        "$name attribute has a reader accessor - $name()"
    );
    is(
        $attr->get_write_method, $name,
        "$name attribute has a writer accessor - $name()"
    );
}
