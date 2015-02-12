use 5.10.0;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'Seq',
    AUTHOR           => q{Thomas Wingo <thomas.wingo@emory.edu>},
    VERSION_FROM     => 'lib/Seq.pm',
    ABSTRACT_FROM    => 'lib/Seq.pm',
    LICENSE          => 'gpl_3',
    PL_FILES         => {},
    MIN_PERL_VERSION => 5.10.0,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
        'Carp' => 0,
        'DBI' => 0,
        'DBD::mysql' => 0,
        'IO::Compress::Gzip' => 0,
        'IO::Uncompress::Gunzip' => 0,
        'YAML::XS' => 0,
        'Moose' => 0,
        'namespace::autoclean' => 0,
        'Scalar::Util' => 0,
        'Time::localtime' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
        'DBD::Mock' => 0,
        'dbi:SQLite' => 0,
    },
    PREREQ_PM => {
        #'ABC'              => 1.6,
        #'Foo::Bar::Module' => 5.0401,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'Seq-*' },
);
