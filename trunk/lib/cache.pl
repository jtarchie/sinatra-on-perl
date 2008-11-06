use strict;
use Carp;
use File::Path;
use File::Basename;

#cache a pages output, so the webserver picks it up -- instead of hittin the application
sub cache_page{
	my ($path, $body) = @_;
	my $full_path = path_filename($path);
	mkpath(dirname($full_path));
	open(FILE, ">$full_path") || croak "Couldn't cache page $path successfully: $!\n";
	print FILE $body;
	close(FILE);
	return undef;
}

#delete the page, so that it can be recreated on the next call
sub expire_page{
	my $path = shift;
	unlink(path_filename($path));
	return undef;
}

#get the full file path where to save the page -- in public_directory
sub path_filename{
	my $path = shift;
	my $public_dir = get_option('public_directory');
	my $full_path = $public_dir . '/' . $path . ".html";
	return $full_path;
}

after(sub{
	my $r = shift;
	#remember that the body gets overriden on anything other than undef
	cache_page($r->request->path, $r->body) if ($r->params->{cache_page} eq "1"); #this return undef if the if statement is true
	return undef; #need to account for possible miss on cache
});

1;