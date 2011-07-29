#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'Net::Amazon::CloudFront' );
}

diag( "Testing Net::Amazon::CloudFront $Net::Amazon::CloudFront::VERSION, Perl $], $^X" );
