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
#
# Plugin details:
##   BUILD 1
#

#
# Configuration
#

# Package name
package CZshare;

# Extend Plugin
@ISA = qw(Plugin);

# Custom packages
use Log;
use Toolbox;
use Configuration;

# Write nicely
use strict;
use warnings;

use utf8;

#
# Routines
#

# Constructor
sub new {
	my $self  = {};
	$self->{CONF} = $_[1];
	$self->{URL} = $_[2];
	$self->{MECH} = $_[3];
	
	$self->{PRIMARY} = $self->{MECH}->get($self->{URL});
	return error("plugin error (primary page error, ", $self->{PRIMARY}->status_line, ")") unless ($self->{PRIMARY}->is_success);
	dump_add(data => $self->{MECH}->content());

	bless($self);
	return $self;
}

# Plugin name
sub get_name {
	return "CZshare";
}

# Filename
sub get_filename {
	my $self = shift;
	
	return $1 if ($self->{PRIMARY}->decoded_content =~ m#<span class="text-darkred"><strong>(.+?)</strong></span>#);
}

# Filesize
sub get_filesize {
	my $self = shift;
	
	return readable2bytes($1) if ($self->{PRIMARY}->decoded_content =~ m#Velikost:</td>\s*<td class="text-left">(.+?)</td>#);
}

# Check if the link is alive
sub check {
	my $self = shift;

	return 1 if ($self->{PRIMARY}->decoded_content =~ m#<span class="nadpis">Download</span>#);
	return -1 if ($self->{PRIMARY}->decoded_content =~ m/error/i);
	return 0;
}

# Download data
sub get_data {
	my $self = shift;
	my $data_processor = shift;
	my $read_captcha = shift;

	my $res;

	if($self->{CONF}->get("login") and $self->{CONF}->get("pass")) {
		#
		# "PROFI" download
		# 

		(my $id) = $self->{PRIMARY}->decoded_content =~ m#<input type="hidden" name="id" value="(.+?)" />#;
		(my $file) = $self->{PRIMARY}->decoded_content =~ m#<input type="hidden" name="file" value="(.+?)" />#;

		# hm, why Im not able to do this with Mechanize?
		$res = $self->{MECH}->post("http://czshare.com/prihlasit.php", {
				prihlasit=>1,
				jmeno=>$self->{CONF}->get("login"),
				heslo=>$self->{CONF}->get("pass"),
				id=>$id,
				file=>$file,
				});

		$_ = $self->{MECH}->content();
		dump_add(data => $_);

		m#http://.+?/$id/.+?/.+?/#;
		$self->{MECH}->request(HTTP::Request->new(GET => $&), $data_processor);

	} else { 
		#
		# FREE download
		#

		return error("No free slots available. Try again later") 
			if ($self->{PRIMARY}->decoded_content =~ m#vyčerpána maximální kapacita FREE downloadů#); # TODO: wait?

		$self->{MECH}->form_with_fields("id","file","ticket"); # "free" form;
		$res = $self->{MECH}->submit_form();
		dump_add(data => $self->{MECH}->content());

		# captcha
		my $captcha;
		do {
			my $cont = $self->{MECH}->content();
			# Get captcha
			my ($captcha_url) = $cont =~ m#<img src="(captcha\.php\?ticket=.+?)" />#ms;
			return error("can't get captcha image") unless ($captcha_url);

			# Download captcha
			my $captcha_data = $self->{MECH}->get($captcha_url)->decoded_content;
			$captcha = &$read_captcha($captcha_data, "png");
			$self->{MECH}->back();

			# Submit captcha form
			$res = $self->{MECH}->submit_form( with_fields => { captchastring => $captcha });
			return 0 unless ($res->is_success);
			dump_add(data => $self->{MECH}->content());
			$self->{MECH}->back() if($self->{MECH}->content() =~ /Error 12/);
		} while ($captcha && $res->decoded_content !~ m#pre_download_form#);

		# generate request
		my($action, $id, $ticket) = $res->decoded_content =~ m#<form name="pre_download_form" action="(.+?)".+name="id" value="(\d+)".+name="ticket" value="(.+?)"#s;# <input type="submit" name="submit_btn" DISABLED value="stahnout " /> 
			my $req = HTTP::Request->new(POST => $action);
		$req->content_type('application/x-www-form-urlencoded');
		$req->content("id=$id&ticket=$ticket");

		$self->{MECH}->request($req, $data_processor);
	}
}

# Amount of resources
Plugin::provide(-1);

# Register the plugin
Plugin::register("^([^:/]+://)?([^.]+\.)?czshare.com/files");

1;