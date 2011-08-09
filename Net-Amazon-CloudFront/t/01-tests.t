#!perl -T
use warnings;
use strict;
use Test::More tests => 2;
use Net::Amazon::CloudFront;
# use Data::Dumper;

# fake data
# see http://bit.ly/rqLWp6
#     (http://docs.amazonwebservices.com/AmazonCloudFront/latest/
#      DeveloperGuide/index.html?RESTAuthentication.html)
my $aws_access_key_id     = '0PN5J17HBGZHT7JJ3X82';
my $aws_secret_access_key = '/Ml61L9VxlzloZ091/lkqVV5X1/YvaJtI9hW4Wr9';
my $cf = Net::Amazon::CloudFront->
  new({ date => "Thu, 14 Aug 2008 17:08:48 GMT",
	aws_access_key_id => $aws_access_key_id,
	aws_secret_access_key => $aws_secret_access_key });

my $request = $cf->_http_request({ resource => "2010-11-01/distribution" });
my $url  = $request->uri();
my $auth = $request->header("Authorization");

# diag(Data::Dumper->Dump([$url],  [qw($url)]));
# diag(Data::Dumper->Dump([$auth], [qw($auth)]));
ok($url  eq "https://cloudfront.amazonaws.com/2010-11-01/distribution",
   "url test");
ok($auth eq "AWS 0PN5J17HBGZHT7JJ3X82:4cP0hCJsdCxTJ1jPXo7+e/YSu0g=",
   "auth test");

1;
