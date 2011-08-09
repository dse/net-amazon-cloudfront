use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
	      NAME                => 'Net::Amazon::CloudFront',
	      AUTHOR              => 'Darren Embry <dse@webonastick.com>',
	      VERSION_FROM        => 'lib/Net/Amazon/CloudFront.pm',
	      ABSTRACT_FROM       => 'lib/Net/Amazon/CloudFront.pm',
	      PL_FILES            => {},
	      LICENSE             => 'perl',
	      PREREQ_PM           => {
				      'Test::More'                 => 0,
				      'LWP::UserAgent::Determined' => 0,
				      'XML::LibXML'                => 0,
				      'URI'                        => 0,
				      'HTTP::Date'                 => 0,
				      'MIME::Base64'               => 0,
				      'Digest::HMAC_SHA1'          => 0,
				     },
	      dist                => { COMPRESS => 'gzip -9f',
				       SUFFIX => 'gz', },
	      clean               => { FILES => 'Net-Amazon-CloudFront-*' },
	     );
