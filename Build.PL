use strict;
use warnings;
use npg_tracking::util::build;


my $builder = npg_tracking::util::build->new(

                 'module_name'    => 'npg_ml_warehouse',
                 'dist_author'    => 'npg <npg@sanger.ac.uk>',
                 'dist_version'   => npg_tracking::util::build->git_tag(),
                 'dist_abstract'  =>
  'Analysis results loader for the multi-lims warehouse, see https://github.com/wtsi-npg/ml_warehouse for the warehouse details.',
                 'license'        => 'gpl',
                 'dist'           => { COMPRESS => 'gzip', SUFFIX => 'gz', },

		 'build_requires'      => {
                    'Devel::Cover'                => 0,
                    'DBD::SQLite'                 => '1.37',
                    'File::Basename'              => 0,
                    'File::Temp'                  => 0,
                    'English'                     => 0,
                    'Moose::Meta::Class'          => 0,
                    'Test::Compile'               => 0,
                    'Test::Deep'                  => 0,
                    'Test::Distribution'          => 0,
                    'Test::Exception'             => 0,
                    'Test::More'                  => 0,
                    'Test::Perl::Critic'          => 0,
                    'Test::Pod'                   => 0,
                    'Test::Pod::Coverage'         => 0,
                    'Test::Warn'                  => 0,
                    'npg_testing::db'             => 0,
                    'npg_tracking::util::build'   => 0,
                    'npg_qc::autoqc::results::qX_yield' => 0,
                 },

                 'requires'            => {
                    'Carp'                      => 0,
                    'DBIx::Class::ResultClass::HashRefInflator' => 0,
                    'List::MoreUtils'           => 0,
                    'Math::Round'               => 0,
                    'Moose'                     => 0,
                    'MooseX::StrictConstructor' => 0,
                    'Readonly'                  => 0,
                    'strict'                    => 0,
                    'Try::Tiny'                 => 0,
                    'warnings'                  => 0,

                    'WTSI::DNAP::Warehouse::Schema'           => 0,
                    'WTSI::DNAP::Warehouse::Schema::Query::IseqFlowcell' => 0,
                    'npg_qc::Schema'                          => 0,
                    'npg_qc::autoqc::qc_store'                => 0,
                    'npg_qc::autoqc::qc_store::options'       => 0,
                    'npg_qc::autoqc::qc_store::query'         => 0,
                    'npg_tracking::glossary::flowcell'        => 0,
                    'npg_tracking::glossary::run'             => 0,
                    'npg_tracking::Schema'                    => 0,
                 },
);

$builder->create_build_script();

1;
