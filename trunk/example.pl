#!/usr/bin/env perl
require 'sinatra.pl';

use strict;

get(':name/:number', {}, sub{
	my $r = shift;
	$r->content_type('text/html');
	$r->htmpl('testing');
});

get(':name/:number.:format', {}, sub{
	my $r = shift;
	$r->content_type('text/plain');
	$r->json($r->params) if $r->params->{format} eq "json";
});

#usage: lighttpd -f lighttpd.conf -D
#goto URLs:
#   http://0.0.0.0:3000/asdf/1234.json
#   http://0.0.0.0:3000/asdf/1234