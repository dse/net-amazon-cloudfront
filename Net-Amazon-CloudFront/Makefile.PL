use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Net::Amazon::CloudFront',
    AUTHOR              => 'Darren Embry <dse@webonastick.com>',
    VERSION_FROM        => 'lib/Net/Amazon/CloudFront.pm',
    ABSTRACT_FROM       => 'lib/Net/Amazon/CloudFront.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Net-Amazon-CloudFront-*' },
);
