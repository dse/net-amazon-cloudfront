package Net::Amazon::CloudFront;
use warnings;
use strict;

use Carp;
use LWP::UserAgent::Determined;
use URI;
use HTTP::Date qw(time2str);
use MIME::Base64 qw(encode_base64);
use Digest::HMAC_SHA1 qw(hmac_sha1);
use XML::Simple;

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

"Amazon CloudFront is a web service for content delivery. It
integrates with other Amazon Web Services to give developers and
businesses an easy way to distribute content to end users with low
latency, high data transfer speeds, and no commitments.

"Amazon CloudFront delivers your static and streaming content using a
global network of edge locations. Requests for your objects are
automatically routed to the nearest edge location, so content is
delivered with the best possible performance. Amazon CloudFront is
optimized to work with other Amazon Web Services, like Amazon Simple
Storage Service (S3) and Amazon Elastic Compute Cloud (EC2). Amazon
CloudFront also works seamlessly with any origin server, which stores
the original, definitive versions of your files. Like other Amazon Web
Services, there are no contracts or monthly commitments for using
Amazon CloudFront---you pay only for as much or as little content as
you actually deliver through the service."

=back

To find out more information about Amazon CloudFront, please visit
L<http://aws.amazon.com/cloudfront/>.

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

Development of this code happens at
L<https://github.com/dse/net-amazon-cloudfront>.

=cut

use fields qw(aws_access_key_id
	      aws_secret_access_key
	      xml_simple
	      ua
	      retry
	      fatal
	      error
	      timeout
	      date
	      cloudfront_host);

our $VERSION = '0.01';

my $KEEP_ALIVE_CACHESIZE = 10;

=head1 METHODS

=head2 new

    my $cf = Net::Amazon::CloudFront->new({
        aws_access_key_id     => $aws_access_key_id,
        aws_secret_access_key => $aws_secret_access_key,
        # --- begin optional parameters ---
        retry                 => 1,
        fatal                 => 1,
        timeout               => 30,
	# --- end optional parameters ---
    });

Create a new CloudFront client object.  Takes a hashref containing the
following keys:

=over 4

=item aws_access_key_id (required)

Use your Access Key ID as the value of the AWSAccessKeyId parameter in
requests you send to Amazon Web Services (when required). Your Access
Key ID identifies you as the party responsible for the request.

=item aws_secret_access_key (required)

Since your Access Key ID is not encrypted in requests to AWS, it could
be discovered and used by anyone. Services that are not free require
you to provide additional information, a request signature, to verify
that a request containing your unique Access Key ID could only have
come from you.

DO NOT INCLUDE THE ACCESS KEY ID OR SECRET ACCESS KEY IN SCRIPTS OR
APPLICATIONS YOU DISTRIBUTE. YOU'LL BE SORRY.

=item retry (optional)

If passed a true value, this library will retry upon errors.  This
uses experimental backoff with retries after 1, 2, 4, 8, 16, and 32
seconds, as recommended by Amazon.

This option defaults to off.

=item timeout (optional)

Specifies a timeout in seconds for HTTP requests.

This option defaults to 30.

=item fatal (optional)

Specifies whether to throw an exception if an Amazon CloudFront action
returns an error.

This option defaults to true.

=back

=cut

sub _set_stage_1_defaults {
    my ($self) = @_;
    $self->{timeout}         = 30;
    $self->{retry}           = 0;
    $self->{cloudfront_host} = "cloudfront.amazonaws.com";
    $self->{fatal}           = 1;
}

sub _set_stage_2_defaults {
    my ($self) = @_;
    $self->{xml_simple} //=
      XML::Simple->new(ForceArray => [qw(DistributionSummary
					 InvalidationSummary
					 Signer
					 CNAME
					 AwsAccountNumber
					 KeyPairId
					 Path)]);
    $self->{date} //= time2str(time());
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

=head2 Exception Handling For All CloudFront Actions

By default, when an Amazon CloudFront action returns an error, the
methods below simply throw an exception by calling croak() with a
single parameter, a string such as "AccessDenied" summarizing the type
of error:

    AccessDenied at /usr/local/bin/frobnitz line 24

A complete list of error types is available at L<http://bit.ly/mXi6Zb>
(L<http://docs.amazonwebservices.com/AmazonCloudFront/latest/APIReference/index.html?Errors.html>).

If the constructor for an object was called with fatal set to false,
the methods below simply return undef.  In this case, you *should*
always check the method's return value.

When fatal is set to false or you catch an exception, more detailed
information about the error is available:

    my $error = $cf->{error};

$error is a hashref that looks like the following example:

    {
      'Error' => {
        'Code' => 'NoSuchDistribution',
        'Type' => 'Sender',
        'Message' => 'The specified distribution does not exist.'
      },
      'xmlns' => 'http://cloudfront.amazonaws.com/doc/2010-11-01/',
      'RequestId' => '843f28f6-c2ac-11e0-93df-2591eca165a6'
    }

Now for an example chunk of code with custom error handling:

    $cf->{fatal} = 0;
    my $dist = $cf->get_distribution("blah");
    if ($dist) {
        # yay!  do stuff ...
    }
    else {
        my $error = $cf->{error};
        # oh noes!  what do i do now?
    }

What with there being more than one way to do everything in Perl and
all, if you want to keep fatal on, you can do something like this
example:

    my $dist = eval { $cf->get_distribution("blah"); }
    if ($@) {
        my $error = $cf->{error};
        # oh noes!  :-(
        return undef;
    }
    if ($dist) {
        # yay!  :-)
    }

=head2 get_distribution_list

    my $list = $cf->get_distribution_list();

Retrieves a list of distributions.

Returns a hashref containing the following keys:

=over 4

=item IsTruncated (boolean)

=item Marker (string)

=item MaxItems (number)

=item NextMarker (string)

=item DistributionSummary (arrayref)

An arrayref, each member of which is a hashref containing the
following keys:

=over 4

=item Id (string)

=item Status (string)

=item IsDeployed (boolean) *

=item IsInProgress (boolean) *

=item InProgressInvalidationBatches (number)

=item LastModifiedTime (string)

=item DomainName (string)

=item S3Origin (hashref)

=over 4

=item DNSName (string)

=item OriginAccessIdentity (string)

=back

=item CustomOrigin (hashref)

=over 4

=item DNSName (string)

=item HTTPPort (string)

=item HTTPSPort (string)

=item OriginProtocolPolicy (string)

=back

=item CNAME (arrayref of strings)

=item Comment (string)

=item Enabled (boolean)

=item TrustedSigners (hashref)

=over 4

=item Self (optional)

=item KeyPairId (arrayref of strings)

=item AwsAccountNumber (arrayref of strings)

=back

=back

=item HTTPRequest (HTTP::Request object) *

=item HTTPResponse (HTTP::Response object) *

=back

More information on the underlying API method and the data it returns
is available at L<http://bit.ly/p7CJvB>
(L<http://docs.amazonwebservices.com/AmazonCloudFront/latest/APIReference/index.html?ListDistributions.html>).

=cut

sub get_distribution_list {
    my ($self) = @_;
    my $data = $self->_request_simple_xml("2010-11-01/distribution");
    if ($data) {
	$data->{IsTruncated} = $data->{IsTruncated} eq "true";
	$data->{MaxItems} += 0;
	foreach my $ds (@{$data->{DistributionSummary}}) {
	    $ds->{IsDeployed}   = $ds->{Status} eq "Deployed";
	    $ds->{IsInProgress} = $ds->{Status} eq "InProgress";
	    $ds->{Enabled}      = $ds->{Enabled} eq "true";
	    $ds->{InProgressInvalidationBatches} += 0;
	}
    }
    return $data;
}

=head2 get_distribution

    my $dist = $cf->get_distribution($id);

Retrieves all information about a distribution.

Returns a hashref containing the following keys:

=over 4

=item Id (string)

=item Status (string)

=item IsDeployed (boolean) *

=item IsInProgress (boolean) *

=item LastModifiedTime (string)

=item InProgressInvalidationBatches (number)

=item DomainName (string)

=item ActiveTrustedSigners (hashref)

=over 4

=back

=item DistributionConfig (hashref)

=over 4

=item S3Origin (hashref)

=over 4

=item DNSName (string)

=item OriginAccessIdentity (string)

=back

=item CustomOrigin (hashref)

=over 4

=item DNSName (string)

=item HTTPPort (string)

=item HTTPSPort (string)

=item OriginProtocolPolicy (string)

=back

=item CallerReference (string)

=item CNAME (arrayref of strings)

=item Comment (string)

=item Enabled (string)

=item DefaultRootObject (string)

=item Logging (hashref)

=over 4

=item Bucket (string)

=item Prefix (string)

=back

=item TrustedSigners (hashref)

=over 4

=item Self (optional)

=item KeyPairId (arrayref of strings)

=item AwsAccountNumber (arrayref of strings)

=back

=back

=item ETag

The ETag value from the HTTP response headers.  Used later when
updating a distribution's configuration or deleting a distribution.

=back

More information on the underlying API method and the data it returns
is available at L<http://bit.ly/pisQXs>
(L<http://docs.amazonwebservices.com/AmazonCloudFront/latest/APIReference/index.html?GetDistribution.html>).

=item HTTPRequest (HTTP::Request object) *

=item HTTPResponse (HTTP::Response object) *

=cut

sub get_distribution {
    my ($self, $id) = @_;
    my $uri = sprintf("2010-11-01/distribution/%s", $id);
    my $data = $self->_request_simple_xml($uri);
    if ($data) {
	$data->{InProgressInvalidationBatches} += 0;
	$data->{IsDeployed}   = $data->{Status} eq "Deployed";
	$data->{IsInProgress} = $data->{Status} eq "InProgress";
	if (my ($dc) = $data->{DistributionConfig}) {
	    $dc->{Enabled} = $dc->{Enabled} eq "true";
	}
	$data->{ETag} = $data->{HTTPResponse}->header("ETag");
    }
    return $data;
}

=head2 post_invalidation

    my $invalidation = $cf->post_invalidation(
      $distribution_id, { Path => ["/image1.jpg", "/image2.jpg"],
                          CallerReference => "my-batch" }
    );

Creates a new object invalidation batch request.  Object invalidation
is one way to remove content from edge caching servers before it is
normally supposed to expire, after having updated that same content on
the origin server.

The CallerReference must be a unique identifier for this particular
invalidation request.  One way to generate one is to create a UUID
using a module such as Data::UUID, Data::GUID, or UUID::Tiny.  This
module doesn't create one by default.

If successful, this method returns a hashref containing the following
keys:

=over 4

=item Status (string)

=item IsCompleted (boolean) *

=item Id (string)

=item CreateTime (string)

=item InvalidationBatch (hashref)

=over 4

=item Path (arrayref of strings)

=item CallerReference (string)

=back

=back

More information on the underlying API method and the data it returns
is available at L<http://bit.ly/pqeGmW>
(L<http://docs.amazonwebservices.com/AmazonCloudFront/latest/APIReference/index.html?CreateInvalidation.html>).

More information about object invalidation is available at
L<http://bit.ly/pSu8SH>
(L<http://docs.amazonwebservices.com/AmazonCloudFront/latest/DeveloperGuide/index.html?Invalidation.html>).

=item HTTPRequest (HTTP::Request object) *

=item HTTPResponse (HTTP::Response object) *

=cut

sub post_invalidation {
    my ($self, $id, $batch) = @_;
    my $uri = sprintf("2010-11-01/distribution/%s/invalidation", $id);
    if (!ref($batch->{Path})) {
	$batch->{Path} = [$batch->{Path}];
    }
    my $content = $self->{xml_simple}->XMLout($batch,
					      RootName => "InvalidationBatch",
					      NoAttr => 1);
    my $data = $self->_request_simple_xml({ method => "POST",
					    resource => $uri,
					    content => $content });
    if ($data) {
	$data->{IsCompleted} = $data->{Status} eq "Completed";
    }
    return $data;
}

=head2 get_invalidation_list

    my $list = $cf->get_invalidation_list($distribution_id);

Retrieves a list of invalidation batches.

Returns a hashref containing the following keys:

=over 4

=item IsTruncated (boolean)

=item Marker (string)

=item MaxItems (number)

=item NextMarker (string)

=item InvalidationSummary (arrayref)

An arrayref of hashrefs, each of which contains the following keys:

=over 4

=item Id (string)

=item Status (string)

=item IsCompleted (boolean) *

=back

=back

=item HTTPRequest (HTTP::Request object) *

=item HTTPResponse (HTTP::Response object) *

=cut

sub get_invalidation_list {
    my ($self, $id) = @_;
    my $uri = sprintf("2010-11-01/distribution/%s/invalidation", $id);
    my $data = $self->_request_simple_xml($uri);
    if ($data) {
	$data->{IsTruncated} = $data->{IsTruncated} eq "true";
	$data->{MaxItems} += 0;
	foreach my $is (@{$data->{InvalidationSummary}}) {
	    $is->{IsCompleted} = $is->{Status} eq "Completed";
	}
    }
    return $data;
}

###############################################################################

BEGIN { if ($ENV{DEBUG}) { require Data::Dumper; } }

sub _request_simple_xml {
    my ($self, $args) = @_;
    if (!ref($args)) {		# is a string, containing resource URI
	$args = { resource => $args };
    }
    my $request  = $self->_http_request($args);
    if ($ENV{DEBUG}) {
	print(("<" x 79) . "\n");
	print($request->as_string());
    }
    my $response = $self->{ua}->request($request);
    if ($ENV{DEBUG}) {
	print((">" x 79) . "\n");
	print($response->as_string());
    }
    my $data = $self->{xml_simple}->XMLin($response->content());
    if ($ENV{DEBUG}) {
	print(("=" x 79) . "\n");
	print(Data::Dumper->Dump([$data], [qw($data)]));
    }
    if ($response->is_success()) {
	$self->{error} = undef;
	if ($data) {
	    $data->{HTTPRequest}  = $request;
	    $data->{HTTPResponse} = $response;
	}
	return $data;
    }
    else {
	$self->{error} = $data;
	if ($self->{fatal}) {
	    croak($self->{error}->{Error}->{Code} //
		  $response->status_line());
	}
	else {
	    return undef;
	}
    }
}

sub _http_request {
    my ($self, $args) = @_;
    $args //= {};
    my $resource = $args->{resource};
    my $unauth = $args->{unauth};
    my $query = $args->{query};
    my $base = "https://" . $self->{cloudfront_host};
    my $uri = URI->new_abs($resource, $base);
    $uri->query_form($query) if defined $query;
    my $url = $uri->as_string();
    my $method = $args->{method} // "GET";
    my $request = HTTP::Request->new($method, $url);
    my $content = $args->{content};
    if (defined $content) {
	$request->content($content);
    }
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

Darren Embry, C<dse at webonastick.com>.

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

RFX Technologies (L<http://www.rfxtechnologies.com/>) for paying me to
write this.  :-)


=head1 COPYRIGHT & LICENSE

Copyright 2011 Darren Embry, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

