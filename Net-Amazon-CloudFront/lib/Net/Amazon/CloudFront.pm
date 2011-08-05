package Net::Amazon::CloudFront;
use warnings;
use strict;

use Carp;
use LWP::UserAgent::Determined;
use XML::LibXML;
use XML::LibXML::XPathContext;
use URI;
use HTTP::Date qw(time2str);
use MIME::Base64 qw(encode_base64);
use Digest::HMAC_SHA1 qw(hmac_sha1);

=head1 NAME

Net::Amazon::CloudFront - Use Amazon's CloudFront content delivery service.

=head1 SYNOPSIS

    use Net::Amazon::CloudFront;

    my $aws_access_key_id     = 'fill me in';
    my $aws_secret_access_key = 'fill me in too';

    my $cf = Net::Amazon::CloudFront->new({
        aws_access_key_id     => $aws_access_key_id,
        aws_secret_access_key => $aws_secret_access_key
    });

    my @dist = $cf->get_distribution_list();

=head1 DESCRIPTION

This module provides a Perlish interface to Amazon's CloudFront
service.

=head2 What Is CloudFront?

From Amazon's blurb:

=over 4

Amazon CloudFront is a web service for content delivery. It integrates
with other Amazon Web Services to give developers and businesses an
easy way to distribute content to end users with low latency, high
data transfer speeds, and no commitments.

Amazon CloudFront delivers your static and streaming content using a
global network of edge locations. Requests for your objects are
automatically routed to the nearest edge location, so content is
delivered with the best possible performance. Amazon CloudFront is
optimized to work with other Amazon Web Services, like Amazon Simple
Storage Service (S3) and Amazon Elastic Compute Cloud (EC2). Amazon
CloudFront also works seamlessly with any origin server, which stores
the original, definitive versions of your files. Like other Amazon Web
Services, there are no contracts or monthly commitments for using
Amazon CloudFront---you pay only for as much or as little content as
you actually deliver through the service.

=back

To find out more information about Amazon CloudFront, please visit:
http://aws.amazon.com/cloudfront/

=head2 What You Need To Use This Module

To use this module you will need to sign up to Amazon Web Services and
provide an "Access Key ID" and "Secret Access Key". If you use this
module, you will incur costs as specified by Amazon. Please check the
costs. If you use this module with your Access Key ID and Secret
Access Key you must be responsible for these costs.

=head2 A Conceptual Understanding Of CloudFront

Basically, you work with distributions.  A distribution is an object
that maps an origin server (the original location of your resources)
to a unique cloudfront.net domain name (e.g.,
"example123.cloudfront.net").  The origin server is either an S3
bucket or any HTTP or HTTPS server (a custom origin).

=head2 Impetus

This module was originally written to provide the Bricolage CMS the
capability to use CloudFront's Object Invalidation API methods to
remove objects from the edge caching servers before updating objects
on the origin server.

In the beginning, this is the only thing this module will be doing.

=head2 About This Code

Development of this code happens here:
http://github.com/dse/net-amazon-cloudfront

=cut

use fields qw(aws_access_key_id
	      aws_secret_access_key
	      libxml
	      ua
	      retry
	      timeout
	      date
	      cloudfront_host);

our $VERSION = '0.01';

my $KEEP_ALIVE_CACHESIZE = 10;

=head1 METHODS

=head2 new

Create a new CloudFront client object.  Takes a hashref:

=over 4

=item aws_access_key_id

Use your Access Key ID as the value of the AWSAccessKeyId parameter in
requests you send to Amazon Web Services (when required). Your Access
Key ID identifies you as the party responsible for the request.

=item aws_secret_access_key

Since your Access Key ID is not encrypted in requests to AWS, it could
be discovered and used by anyone. Services that are not free require
you to provide additional information, a request signature, to verify
that a request containing your unique Access Key ID could only have
come from you.

DO NOT INCLUDE THE ACCESS KEY ID OR SECRET ACCESS KEY IN SCRIPTS OR
APPLICATIONS YOU DISTRIBUTE. YOU'LL BE SORRY.

=item retry

If passed a true value, this library will retry upon errors.  This
uses experimental backoff with retries after 1, 2, 4, 8, 16, and 32
seconds, as recommended by Amazon.

This option defaults to off.

=item timeout

Specifies a timeout in seconds for HTTP requests.

Defaults to 30.

=back

=cut

sub _set_stage_1_defaults {
    my ($self) = @_;
    $self->{timeout}         = 30;
    $self->{retry}           = 0;
    $self->{cloudfront_host} = "cloudfront.amazonaws.com";
}

sub _set_stage_2_defaults {
    my ($self) = @_;
    $self->{libxml}          //= XML::LibXML->new();
    $self->{date}            //= time2str(time());
}

sub new {
    my ($class, $args) = @_;
    my $self = fields::new($class);
    $self->_set_stage_1_defaults();

    if ($args && ref($args) eq "HASH") {
	while (my ($k, $v) = each(%$args)) {
	    $self->{$k} = $v;
	}
    }

    if ($self->{retry}) {
	$self->{ua} //= LWP::UserAgent::Determined->
	  new(keep_alive => $KEEP_ALIVE_CACHESIZE,
	      requests_redirectable => [qw(GET DELETE PUT)]);
	$self->{ua}->timing("1,2,4,8,16,32");
    }
    else {
	$self->{ua} //= LWP::UserAgent->
	  new(keep_alive => $KEEP_ALIVE_CACHESIZE,
	      requests_redirectable => [qw(GET DELETE PUT)]);
    }
    $self->{ua}->timeout($self->{timeout});
    $self->{ua}->env_proxy();

    $self->_set_stage_2_defaults();
    return $self;
}

=head2 get_distribution_list

    my @dist = $cf->get_distribution_list();

Retrieves a list of distributions.  Each will be a hashref containing
the following keys:

=over 4

=item id

The distribution's identifier.  Example: "EDFDVBD632BHDS5"

=item status

"Deployed" or "InProgress"

=item deployed

A boolean indicating whether the distribution is deployed.

=item in_progress

A boolean indicating whether the distribution is in progress.

=item last_modified_time

The date and time the distribution was a modified, as a string of the
format "2009-11-19T19:37:58Z".

=item domain_name

The distribution's domain name.  Example: "d604721fxaaqy9.cloudfront.net"

=item s3_origin

If the distribution uses an Amazon S3 origin, a hashref containing the
following keys:

=over 4

=item dns_name

The S3 origin's domain name.  Example: "mybucket.s3.amazonaws.com"

=back

=item custom_origin

If the distribution uses a custom origin, a hashref containing the
following keys:

=over 4

=item dns_name

The origin's domain name.

=item http_port

=item https_port

The HTTP and/or HTTPS port the custom origin listens on.

=item origin_protocol_policy

"http-only" or "match-viewer".

=back

=item cname

An array reference containing the CNAMEs.

=item enabled

A boolean indicating whether the distribution is enabled.

=back

=cut

sub get_distribution_list {
    my ($self) = @_;
    my $request = $self->_http_request({ resource => "2010-11-01/distribution" });
    my $response = $self->{ua}->request($request);
    croak($response->status_line()) unless $response->is_success();
    my $doc = $self->{libxml}->parse_string($response->content());
    my $xpc = XML::LibXML::XPathContext->new($doc);
    $xpc->registerNs("cf", "http://cloudfront.amazonaws.com/doc/2010-11-01/");
    my @distribution;
    foreach my $dsnode ($xpc->findnodes("//cf:DistributionSummary")) {
	my $distribution = {};
	my $id          = $xpc->findvalue("cf:Id", $dsnode);
	my $status      = $xpc->findvalue("cf:Status", $dsnode);
	my $domain_name = $xpc->findvalue("cf:DomainName", $dsnode);
	my $ipib        = $xpc->findvalue("cf:InProgressInvalidationBatches",
					  $dsnode) || 0;
	my @cname       = (map { $_->textContent() }
			   $xpc->findnodes("cf:CNAME", $dsnode));
	my $enabled     = $xpc->findvalue("cf:Enabled", $dsnode) eq "true";
	my $lmtime      = $xpc->findvalue("cf:LastModifiedTime", $dsnode);
	$distribution->{id} = $id;
	$distribution->{status} = $status;
	$distribution->{deployed} = $status eq "Deployed";
	$distribution->{in_progress} = $status eq "InProgress";
	$distribution->{domain_name} = $domain_name;
	$distribution->{cname} = \@cname;
	$distribution->{enabled} = $enabled;
	$distribution->{ipib} = $ipib;
	$distribution->{last_modified_time} = $lmtime;
	if (my ($s3onode) = $xpc->findnodes("cf:S3Origin", $dsnode)) {
	    my $s3o = $distribution->{s3_origin} = {};
	    $s3o->{dns_name} = $xpc->findvalue("cf:DNSName", $s3onode);
	}
	elsif (my ($conode) = $xpc->findnodes("cf:CustomOrigin", $dsnode)) {
	    my $co = $distribution->{custom_origin} = {};
	    $co->{dns_name}   = $xpc->findvalue("cf:DNSName", $conode);
	    $co->{http_port}  = $xpc->findvalue("cf:HTTPPort", $conode);
	    $co->{https_port} = $xpc->findvalue("cf:HTTPSPort", $conode);
	    $co->{origin_protocol_policy} =
	      $xpc->findvalue("cf:OriginProtocolPolicy", $conode);
	}
	push(@distribution, $distribution);
    }
    return @distribution;
}

sub get_date {
    my ($self) = @_;
    my $request = $self->_http_request({ resource => "date", unauth => 1 });
    my $response = $self->{ua}->request($request);
    croak($response->status_line()) unless $response->is_success();
    print($response->as_string());
}

use constant CLOUDFRONT_HOST => "cloudfront.amazonaws.com";

sub _http_request {
    my ($self, $args) = @_;
    $args //= {};
    my $resource = $args->{resource};
    my $unauth = $args->{unauth};
    my $query = $args->{query} // {};
    my $base = "https://" . $self->{cloudfront_host};
    my $uri = URI->new_abs($resource, $base);
    $uri->query_form($query);
    my $url = $uri->as_string();
    my $request = HTTP::Request->new(GET => $url);
    if (!$unauth) {
	my $date = $self->{date};
	my $sign = encode_base64(hmac_sha1($date,
					   $self->{aws_secret_access_key}),
				 "");
	$request->header(Date => $date);
	$request->header(Authorization =>
			 "AWS " . $self->{aws_access_key_id} . ":" . $sign);
    }
    return $request;
}
	
=head1 AUTHOR

Darren Embry, C<< <dse at webonastick.com> >>

=cut

1; # End of Net::Amazon::CloudFront

__END__

=head1 BUGS

Please report any bugs or feature requests to C<bug-net-amazon-cloudfront at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-Amazon-CloudFront>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Net::Amazon::CloudFront

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Net-Amazon-CloudFront>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Net-Amazon-CloudFront>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Net-Amazon-CloudFront>

=item * Search CPAN

L<http://search.cpan.org/dist/Net-Amazon-CloudFront>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2011 Darren Embry, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

