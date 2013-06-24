#!/usr/bin/perl

# statuscrawler - Crawls all pages on a specified url, logs all statuses and mails a report.
# Written by Ole Fredrik Skudsvik <ole.skudsvik@gmail.com>

use POSIX;
use LWP;
use URI;
use Email::Send;
use Getopt::Std;

use strict;
use warnings;
no warnings 'recursion';

##############################
#  Configuration variables.  #
##############################

my @ignoreStatusCodes = ( "200" );
my $reportSenderAddress = 'crawler@mydomain.com';
my $userAgent = "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.31 (KHTML, like Gecko) Chrome/26.0.1410.43 Safari/537.31";

################################################################
# Do not edit from here (unless you know what you are doing).  #
################################################################

my %options;
my %urlList;
my %brokenLinks;

sub getPageContent {
	my $url = shift;
	my $cli = LWP::UserAgent->new();
	$cli->agent($userAgent);	
	$cli->timeout(10);
	
	return $cli->get($url);
}

sub getPageHead {
	my $url = shift;
	my $cli = LWP::UserAgent->new();
	$cli->agent($userAgent);
	$cli->timeout(10);

	return $cli->head($url);
}


# Returns true if the statuscode given as parameter is in the @ignoreStatusCodes list, false otherwise.
sub ignoreStatusCode {
	my $statusCode = shift;
	foreach(@ignoreStatusCodes) { return 1 if ($statusCode eq $_); }
	return 0;
}

# crawl(hashRef, url)
# Returns the urls (<a href> and <img src>) contained in the url specified.
sub crawl {
	my ($urlList, $rawUrl, $levelCountLimit, $levelCount, $referrer) = @_;
	my $url = URI->new($rawUrl);
	my $referrerUri;
	my @foundUrls;
	my $pageReq;

	$levelCount = 0 if (!$levelCount);

	# Do not continue scan in this 'thread' when we reach the levelcount.
	if ($levelCountLimit && ($levelCount > $levelCountLimit) && ($levelCountLimit != -1)) {
		return;
	}

	$levelCount++;

	return if ($rawUrl =~ m/#[A-Za-z0-9]+$/); # Ignore anchor urls.
	return if (exists($urlList{$rawUrl})); # Do not crawl urls we already have crawled.
	return if ($rawUrl eq "/");

	# Do not scan pictures, etc for urls. Just send a HEAD to get the status.
	if ($rawUrl =~ m/\.(jpg|jpeg|png|tiff|gif|bmp|zip|tar|tar\.gz|7z|exe|ogg|mp3|flac|sfw|pdf|dmg|iso|img|avi|mov|mpeg|wmv|wav|css)$/i) {
		$pageReq = getPageHead($rawUrl);
		print($rawUrl . " " . $pageReq->status_line . "\n");
		$urlList->{$rawUrl} = $pageReq->status_line;
		return;
	}

	$pageReq = getPageContent($url->as_string);
	$urlList->{$rawUrl} = $pageReq->status_line;
	
	print($rawUrl . " " . $pageReq->status_line . "\n");

	# Just perform one level scans of url's outside out domain.
	if ($referrer) {
		if ( (substr($referrer, 0, 4) eq "http") && (substr($rawUrl, 0, 4) eq "http") ) {
			$referrerUri = URI->new($referrer);
			return if (index($url->host, $referrerUri->host) < 0);
		}
	}

	# Do not proceed if the content-type contains image.	
	return if (substr($pageReq->content_type, 0, 5) eq "image"); 

	# Return if the page request wasn't successful.
	return if (!$pageReq->is_success);

	# Parse the content for any new urls.
	my $data = $pageReq->decoded_content;
	while ($data =~ /(?:href|src)\s*=\s*["'](?!mailto:|\#|[\.]{2})([a-zA-Z0-9\.\-\/%_\?=,;:\+\#\$\*\!\@\&\~\^\"\']+)["'](?:\s+|\>|\/)/g) {
		my $newUrl;

		next if (($1 =~ m/^(javascript:|tel:|sms:|skype:).*/));

		if (substr($1, 0, 2) eq "//") {
			$newUrl = $url->scheme . ":" . $1;
		} elsif ( (substr($1, 0, 4) ne "http") && (length($1) > 1) ) {
			# Strip leading slashes;
			my $reqUri = $1;
			$reqUri =~ s/^\/+//;

			my $tmpUrl = $url->scheme . "://" . $url->host . "/" . $reqUri;
			$newUrl = $tmpUrl if (!exists($urlList->{$tmpUrl}));
		} else {
			$newUrl = $1;
		}
	
		push @foundUrls, $newUrl if ($newUrl);
	}

	foreach (@foundUrls) {
		crawl($urlList, $_, $levelCountLimit, $levelCount, $rawUrl);
	}
}

# makeReport(inputHash)
sub makeReport {
	my $inputHash = $_[0];
	my %sortedList;
	my $urlCnt = 0;
	my $reportMsg = "";

	foreach (keys(%{$inputHash})) {
		$urlCnt++;

		my $statusCode = $inputHash->{$_};
		$statusCode =~ s/(\d+).*/$1/;

		push @{$sortedList{$inputHash->{$_}}}, $_ if (!ignoreStatusCode($statusCode));
	}

	foreach(keys(%sortedList)) {
		$reportMsg .= sprintf("%s:\n", $_);
		foreach(@{$sortedList{$_}}) { $reportMsg .= sprintf("  %s\n", $_); }
		$reportMsg .= "\n";
	}

	return $reportMsg;;
}

sub sendMail {
	my ($to, $from, $subject, $message) = @_;
	my $sender = Email::Send->new({mailer => 'SMTP'});

	$sender->mailer_args([Host => 'smtp.vgnett.no']);
	$message = sprintf("To: %s\nFrom: %s\nSubject: %s\n\n%s", $to, $from, $subject, $message);
	
	$sender->send($message);
}


getopts("hl:m:", \%options);

if (defined($options{l}) && !($options{l} =~ m/^(\d+)$/)) {
	die("Level must be a number.\n");
}

if (!defined($options{l}) || $options{l} < 1) {
	$options{l} = -1;
}

if (!defined($options{m})) {
	die("You need to specify an email address to receieve the report.\n");
}

print("Will crawl " . $options{l} . " levels.\n") if $options{l} > -1;

foreach (@ARGV) {
	crawl(\%urlList, $_, $options{l});
}

my $report = makeReport(\%urlList);

if (length($report) > 5) {
	foreach my $mailAddr (split(",", $options{m})) {
		if ($mailAddr =~ m/[A-Za-z0-9.-]+@[A-Za-z0-9.-]/) {
			print("Sending report to " . $mailAddr . ".\n");
			sendMail($mailAddr, $reportSenderAddress, 'HTTP status crawler report', $report);
		}
	}
}
