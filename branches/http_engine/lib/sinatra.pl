package Sinatra::Base;
use Data::Dumper;

sub dump{
	return Dumper(shift);
}
sub alias_method{
	my ($class, $new_method, $old_method) = @_;
	no strict 'refs';
	*{$class ."::" . $new_method} = $class->can($old_method);
	#print "alias_method: $old_method -> $new_method\n";
}

sub alias_method_chain{
	my ($class, $method_name, $transition) = @_;
	$class->alias_method("$method_name" . "_without_" . $transition, $method_name);
	$class->alias_method("$method_name", "$method_name" . "_with_" . $transition);
}

sub attr_reader{
	my ($class, @names) = @_;
	no strict 'refs';
	foreach my $name (@names) {
		*{$class . "::" . $name} = sub {return shift->{$name};};
	}
}

sub attr_accessor{
	my ($class, @names) = @_;
	no strict 'refs';
	foreach my $name (@names) {
		*{$class . "::" . $name} = sub {my($self,$value)=@_; $self->{$name}=$value if defined $value; return $self->{$name};};
	}
	
}

package Sinatra::Result;
use base 'Sinatra::Base';
use strict;

sub new{
	my ($class, $block, $params, $status) = @_;
	return bless({
		'block' => $block,
		'params' => $params || {},
		'status' => $status
	}, $class);
}
Sinatra::Result->attr_reader(qw/block params status/);

package Sinatra::Event;
use base 'Sinatra::Base';
use strict;
use URI::Escape;

my $URI_CHAR = '[^/?:,&#\.]';
my $PARAM = "(:($URI_CHAR+)|\\*)";
my $SPLAT = '(.*?)';

sub new{
	my ($class, $path, $options, $block) = @_;
	my $splats = 0;
	my $self = {
		'path' => uri_escape($path),
		'block' => $block,
		'param_keys' => [],
		'options' => $options
	};
	my $regex = $path;
	$regex =~ s/$PARAM/
	my $match = $&;
	if ($match eq "*") {
		push(@{$self->{param_keys}}, "_splat_$splats");
		$splats++;
		$SPLAT;
	} else{
		push(@{$self->{param_keys}}, $2);
		"($URI_CHAR+)";
	}/ge;
	
	$self->{'pattern'} = qr/^$regex\/{0,1}$/;
	return bless($self, $class);
}

sub invoke {
	my ($self, $request) = @_;
	my (@splats, $params);
	
	if (my $agent = $self->{options}->{agent}) {
		return unless $request->user_agent =~ $agent;
		$params->{agent} = $1;
	}
	if (my $host = $self->{options}->{host}) {
		return unless $request->hostname eq $host;
	}
	return unless my @values = ($request->request_uri =~ $self->{pattern});
	$params = $self->{options};
	$params->{$_} = uri_unescape(shift(@values)) foreach @{$self->{param_keys}};
	push(@splats, $params->{$_}) foreach grep {/^_splat_\d+$/} keys %{$params};
	unless (scalar @splats == 0) {
		delete $params->{$_} foreach grep {/^_splat_\d+$/} keys %{$params};
		$params->{splat} = \@splats;
	}
	return Sinatra::Result->new($self->{block}, $params, 200);
}

package Sinatra::Helper;
use base 'Sinatra::Base';
use strict;
use HTML::Template;
use JSON::Any;

sub env_html{
	my $output = "";
	$output .= $_ . " = " . $ENV{$_}  . "<br>" foreach sort keys %ENV;
	return "<p>$output</p>";
}

sub redirect{
	my ($self, $url) = @_;
	$self->status(302);
	$self->header('Location', $url);
	$self->body('Moving to location ' . $url);
	die "halt";
}

sub render{
	my ($self, $renderer, $template, $options) = @_;
	my $method_name = "render_" . $renderer;
	my $filename = $self->template_filename($renderer, $template, $options);
	$self->$method_name($filename, $options);
}

sub template_filename{
	my ($self, $renderer, $template, $options) = @_;
	my $path = ($options->{view_directory} || $self->options->{view_directory}) . "/" . $template . "." . $renderer;
	return $path;
}

sub htmpl{
	my $self = shift;
	$self->render('htmpl', @_);
}

sub render_htmpl{
	my($self, $filename, $options) = @_;
	my $t = HTML::Template->new('filename' => $filename, die_on_bad_params => 0, blind_cache => 1);
	$t->param($self->params);
	return $t->output();
}

sub json{
	my $self = shift;
	return JSON::Any->new->encode(@_);
}

package Sinatra::Context;
use base 'Sinatra::Base';
use strict;
use base 'Sinatra::Helper';
use HTTP::Status qw(status_message);
our $AUTOLOAD;

sub new {
	my ($class, $request, $response, $options, $route_params) = @_;
	return bless {
		'request' => $request,
		'response' => $response,
		'options' => $options,
		'route_params' => $route_params
	}, $class;
}
Sinatra::Context->attr_accessor(qw/request status response options route_params/);

sub params{
	my $self = shift;
	unless (defined($self->{params})) {
		$self->{params}->{$_} = $self->request->param($_) foreach ($self->request->param);
		$self->{params}->{$_} = $self->route_params->{$_} foreach keys %{$self->route_params};
		$self->{params} ||= {};
	}
	return $self->{params};
}

sub run{
	my ($self, $code) = @_;
	my $body = $code->($self);
	$self->response->body($body) if defined $body;
}

sub header{
	my ($self, $header, $value) = @_;
	$self->response->headers->header($header => $value);
}

sub content_type{
	my ($self, $content_type) = @_;
	$self->response->headers->header('Content-type' => $content_type);
}

sub AUTOLOAD{
	my $self = shift;
	my $name = $AUTOLOAD;
	$name =~ s/.*://;
	$self->response->$name(@_);
}

sub output{
	my $self = shift;
	
	if ($self->status == 204 || $self->status == 304) {
		delete $self->{headers}->{'Content-type'};
	}
	$self->header('Content-length', length($self->body()));
	my $output = 'HTTP/1.1 ' . $self->status . " " . status_message($self->status) . "\n";
	$output .= join("\n", map {$_ . ": " . $self->{headers}->{$_}} keys %{$self->{headers}}) . "\n\n";
	$output .= ($self->body || '');
	return $output;
}

package Sinatra::Application;
use base 'Sinatra::Base';
use strict;

my (%events, %filters, %errors, %templates);
sub new{
	my $class = shift;

	my $self = {};
	bless($self, $class);
	$self->load_defaults;
	return $self;
}

sub load_defaults{
	my $self = shift;
	$self->options({
		'environment' => $ENV{'SINATRA_ENVIRONMENT'} || 'development',
		'view_directory' => ($ENV{'SINATRA_ROOT'} || $ENV{'DOCUMENT_ROOT'} || '.') . '/views',
		'public_directory' => ($ENV{'SINATRA_ROOT'} || $ENV{'DOCUMENT_ROOT'} || '.') . '/public',
	});
	$errors{'standard'} = sub{
		my $self = shift;
		$self->content_type('text/html');
		return '<p><b>'.$self->params->{_error_msg} . '</b></p><p>An error occurred. Fix it!</p>' . $self->env_html;
	};
	$errors{'not_found'} = sub{
		my $self = shift;
		$self->content_type('text/html');
		return 'Could not the request path: ' . $self->request->request_uri . $self->env_html;
	};
}

sub options{
	my ($self, $options) = @_;
	if (defined $options) {$self->{options}->{$_} = $options->{$_} foreach keys %{$options}};
	return $self->{options};
}

sub run{
	my $self = shift;

	use HTTP::Engine;
	my $engine = HTTP::Engine->new(
		interface => {
			module => 'FCGI',
			request_handler => sub {
				my $request = shift;
				$self->dispatch(
					$request, 
					HTTP::Engine::Response->new
				);
			}
		}
	);
	$engine->run;
}

sub define_event{
	my ($self, $method, $path, $options, $code) = @_;
	push(@{$events{$method}}, Sinatra::Event->new($path, $options, $code));
}

sub define_filter{
	my ($self, $action, $code) = @_;
	push(@{$filters{$action}}, $code);
}

sub define_error{
	my ($self, $type, $code) = @_;
	unless (ref($type) eq 'CODE') {
		$errors{$type} = $code;
	} else{
		$errors{'standard'} = $type;
	}
}

sub define_template{
	my ($self, $name, $body) = @_;
	$templates{$name} = $body;
}

sub lookup{
	my ($self, $request) = @_;
	my $method = lc($request->method);
	foreach my $event (@{$events{$method}}) {
		my $invoke = $event->invoke($request);
		return $invoke if defined $invoke;
	}
	return Sinatra::Result->new($errors{'not_found'}, undef, 404);
}

sub dispatch{
	my ($self, $request, $response) = @_;
	$self->load_defaults if $self->options->{environment} eq "development";
	my $result = $self->lookup($request);
	my $context = Sinatra::Context->new($request, $response, $self->options, $result->params);
	$context->status($result->status);
	
	eval {
		$context->run($_) foreach @{$filters{before}};
		$context->run($result->block());
		$context->run($_) foreach @{$filters{after}};
	};
	if ($@) {
		unless ($@ eq "halt") {
			warn "Error occured $0: " . $@;
			$context->status(500);
			$context->params->{_error_msg} = $@;
			$context->run($errors{$@} || $errors{standard});
		}
	}
	$context->body("") if lc($request->method) eq "head";
	return $response;
}

package main;
use strict;

my $application = Sinatra::Application->new();

sub get($$&) {$application->define_event('get',@_);}
sub post($$&) {$application->define_event('post',@_);}
sub head($$&) {$application->define_event('head',@_);}
sub destroy($$&) {$application->define_event('delete',@_);}
sub put($$&) {$application->define_event('put',@_);}

sub before(&) {$application->define_filter('before', @_);}
sub after(&) {$application->define_filter('after', @_);}

sub error {$application->define_error(@_);}
sub not_found {$application->define_error('not_found',shift);}
sub set_options{
	$application->options(shift);
}
sub set_option{
	my ($key, $value) = @_;
	set_options({$key => $value});
}
sub get_option{
	my $key = shift;
	return $application->options->{$key};
}
sub configure {
	my $code = pop @_;
	$code->($application) if (scalar(@_) == 0 || grep {$_ eq $application->options->{environment}} @_);
}
sub dispatch {
	my $request = shift;
	$application->dispatch($request);
}
sub application{return $application;}

BEGIN {
	$ENV{'SINATRA_ENVIRONMENT'} = 'task' if defined $ARGV[0];
}
END {
	my $taskname = 'task_' . ($ARGV[0] || '');
	if (main->can($taskname)) {
		print "Running task " . $ARGV[0] . " on pid:" . $$ . "\n";
		set_option('in_task', 1);
		main->$taskname();
	} else{
		$application->run();
	}
}