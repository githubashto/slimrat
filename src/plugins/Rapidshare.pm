# slimrat - Rapidshare plugin
#
# Copyright (c) 2008-2009 Přemek Vyhnal
# Copyright (c) 2009 Tim Besard
#
# This file is part of slimrat, an open-source Perl scripted
# command line and GUI utility for downloading files from
# several download providers.
# 
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following
# conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# Authors:
#    Přemek Vyhnal <premysl.vyhnal gmail com>
#    Tim Besard <tim-dot-besard-at-gmail-dot-com>
#
# Plugin details:
##   BUILD 2
#

#
# Configuration
#

# Package name
package Rapidshare;

# Extend Plugin
@ISA = qw(Plugin);

# Custom packages
use Log;
use Toolbox;
use Configuration;
use HTTP::Request;

# Write nicely
use strict;
use warnings;


#
# Routines
#

# Constructor
sub new {
	my $self  = {};
	$self->{CONF} = $_[1];
	$self->{URL} = $_[2];
	$self->{MECH} = $_[3];
	
	$self->{CONF}->set_default("interval", 0);
	
	# Workaround to fix Rapidshare's empty content-type, which makes forms() fail
	# Follow: http://code.google.com/p/www-mechanize/issues/detail?id=124
	my $req = new HTTP::Request("GET", $self->{URL});
	$self->{PRIMARY} = $self->{MECH}->request($req);
	$self->{PRIMARY}->content_type('text/html');
	$self->{MECH}->_update_page($req, $self->{PRIMARY});
	
	return error("plugin error (primary page error, ", $self->{PRIMARY}->status_line, ")") unless ($self->{PRIMARY}->is_success);
	dump_add(data => $self->{MECH}->content());

	bless($self);
	return $self;
}

# Plugin name
sub get_name {
	return "Rapidshare";
}

# Filename
sub get_filename {
	my $self = shift;
	
	return $1 if ($self->{PRIMARY}->decoded_content =~ m/<p class="downloadlink">http:\/\/[^<]+\/([^<]+) </);
}

# Filesize
sub get_filesize {
	my $self = shift;
	
	return readable2bytes($1) if ($self->{PRIMARY}->decoded_content =~ m/<p class="downloadlink">http:\/\/[^<]+ <font[^>]*>\| ([^<]+)<\/font/);
}

# Check if the link is alive
sub check {
	my $self = shift;

	# Check if the download form is present
	return 1 if ($self->{PRIMARY}->decoded_content =~ m/form id="ff" action/);
	return -1;
}

# Download data
sub get_data {
	my $self = shift;
	my $data_processor = shift;
	
	# Click the "Free" button
	# TODO: eval get_data to prevent the need of thousand return error(blabla) calls
	#       OR make sure slimrat doesn't die when a threads exist abnormally
	$self->{MECH}->form_id("ff") || return error("plugin failure (could not find form)");
	my $res = $self->{MECH}->submit_form();
	return error("plugin failure (secondary page error, ", $res->status_line, ")") unless ($res->is_success);
	dump_add(data => $self->{MECH}->content());
	
	# Process the resulting page
	while(1) {
		my $wait;
		$_ = $res->decoded_content."\n"; 

		if(m/reached the download limit for free-users/) {
			($wait) = m/Or try again in about (\d+) minutes/sm;
			info("reached the download limit for free-users");
			
		} elsif(($wait) = m/Currently a lot of users are downloading files\.  Please try again in (\d+) minutes or become/) {
			info("currently a lot of users are downloading files");
		} elsif(($wait) = m/no available slots for free users\. Unfortunately you will have to wait (\d+) minutes/) {
			info("no available slots for free users");

		} elsif(m/already downloading a file/) {
			info("already downloading a file");
			$wait = 1;
		} else {
			last;
		}
		
		if ($self->{CONF}->get("interval") && $wait > $self->{CONF}->get("interval")) {
			info("should wait $wait minutes, interval-check in " . $self->{CONF}->get("interval") . " minutes");
			$wait = $self->{CONF}->get("interval");
		}
		wait($wait*60);
		$res = $self->{MECH}->reload();
		dump_add(data => $self->{MECH}->content());
	}
	
	# Extract the download URL
	my ($download, $wait) = m/form name="dlf" action="([^"]+)".*var c=(\d+);/sm;
	return error("plugin error (could not extract download link)") unless $download;
	wait($wait);

	$self->{MECH}->request(HTTP::Request->new(GET => $download), $data_processor);
}

# Amount of resources
Plugin::provide(1);

# Register the plugin
Plugin::register("^([^:/]+://)?([^.]+\.)?rapidshare.com");

1;