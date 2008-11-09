use strict;
use Carp;
use File::Path;
use File::Basename;

#cache a pages output, so the webserver picks it up -- instead of hitting the application
#please keep in mind that this negates all before/after tasks assigned within the application
#params:
#   $path = the request path that will match to the file
#   $body = the body of the file (right now text only supported)
#   $ext = the extension to append to the file (optional and defaults to ".html")
sub cache_page{
	my ($path, $body, $ext) = @_;
	my $full_path = path_filename($path, $ext);
	mkpath(dirname($full_path));
	open(FILE, ">$full_path") || croak "Couldn't cache page $path successfully: $!\n";
	print FILE $body;
	close(FILE);
	return undef;
}

#delete the page, so that it can be recreated on the next call
#params:
#   $path = the request path that will match to file
#   $ext = the extension to append to the file (optional and defaults to ".html")
sub expire_page{
	my ($path, $ext) = @_;
	unlink(path_filename($path, $ext));
	return undef;
}

#get the full file path where to save the page -- in app option public_directory
#params:
#   $path = the request path that will match to the file
#   $ext = the extension to append to the file (optional and defaults to ".html")
sub path_filename{
	my ($path, $ext) = @_;
	$ext ||= ".html";
	my $public_dir = get_option('public_directory');
	my $full_path = $public_dir . '/' . $path . $ext;
	return $full_path;
}

#this is an after filter used to identify which requests to cache
#it will add an overhead to each request, so make sure to benchmark
after(sub{
	my $r = shift;
	#remember that the body gets overriden on anything other than undef
	cache_page($r->request->path, $r->body, $r->params->{cache_page} ne "1" ? "." . $r->params->{cache_page} : undef) if (exists $r->params->{cache_page}); #this return undef if the if statement is true
	return undef; #need to account for possible miss on cache
});

1;