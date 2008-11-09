use strict;
use IO::Pipe;
use JSON::Any;

#inter process communication
my $pipe = IO::Pipe->new;

sub start_job_server{
	my $pid = fork;
	if (! defined $pid) {
		die "Cannot start up a background process. Apparently forking is not supported.\n";
	} elsif($pid == 0) { #the background job server
		$pipe->reader;
		receive_job();
	} else { #the CGI/FCGI process
		$pipe->writer;
		$pipe->autoflush;
	}
}

#called from parent process and sends job to receiver
sub send_job{
	my($method, @arguments) = @_;
	#send the dispatch to the job server
	my $line = JSON::Any->objToJson({
		'method' => $method,
		'arguments' => \@arguments
	});
	print $pipe $line . "\n";
}

sub receive_job{
	while(my $line = <$pipe>) {
		my $dispatch = JSON::Any->jsonToObj($line);
		#check to make sure this method exists
		my $method = $dispatch->{method};
		if (my $call = main->can($method)) {
			eval{
				$call->(@{$dispatch->{arguments}});
			};
		} #we don't do anything if we can't -- not are problem
	}
}

1;