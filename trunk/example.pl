#!/usr/bin/env perl -w
require 'lib/sinatra.pl';
require 'lib/cache.pl';
require 'lib/background.pl';

use strict;
use DBI;
use Rose::DB::Object::Loader;

configure(sub{
	my $loader = Rose::DB::Object::Loader->new(
		db_dsn       => 'dbi:SQLite:dbname=tmp/test.sql',
		base_classes => [qw(Rose::DB::Object Rose::DB::Object::Helpers)]
	);
	$loader->make_classes;
	start_job_server();
});

# list - GET /user
get('user', {cache_page=>'1'}, sub{
	my $r = shift;
	$r->content_type('text/plain');
	my $users = [map {$_->as_tree} @{User::Manager->get_users()}];
	return $r->json($users);
});

# an example of how to expire a page
# using a background job
get('expire', {}, sub{
	send_job('expire_page', 'user');
	return 'Expired successful';
});

# create - POST /user
post('user', {}, sub{
	my $r = shift;
	$r->content_type('text/plain');
	delete $r->params->{id}; #someone might override different ID
	my $user = User->new('email'=>$r->params->{email}, 'password'=>$r->params->{password});
	if ($user->save) {
		$r->status(200);
		return $user->id;
	} else{
		$r->status(500);
		return 'Error cannot create new user';
	}
});

# show - GET /user/id
get('user/:id', {'cache_page'=>'1'}, sub{
	my $r = shift;
	$r->content_type('text/plain');
	my $user = User->new(id=>$r->params->{id});
	$user->load('speculative' => 1);
	if ($user->not_found) {
		$r->status(404);
	} else{
		return $r->json($user->as_tree);
	}
});

# update - PUT /user/1
put('user/:id', {}, sub {	
	my $r = shift;
	my $user = User->new(id=>$r->params->{id});
	$user->load(speculative=>1);
	if ($user->not_found) {
		$r->status(404);
	} else{
		$user->email = $r->params->{email};
		$user->password = $r->params->{password};
		$user->save;
		$r->status(202);
	}
});

# destroy - DELETE /user/1
destroy('user/:id', {}, sub{	
	my $r = shift;
	my $user = User->new(id=>$r->params->{id});
	$user->delete;
	$r->status(202);
});

sub task_setup{
	my $dbh = DBI->connect('dbi:SQLite:dbname=tmp/test.sql');
	$dbh->do(qq~DROP TABLE IF EXISTS users;~);
	$dbh->do(qq~CREATE TABLE users (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			email TEXT,
			password TEXT,
			created_at TEXT
		);~);
	$dbh->do(qq~	
		INSERT INTO users VALUES (NULL, 'alf\@cats.com', 'soygreen123', datetime('now'));
	~);
	$dbh->do(qq~
		INSERT INTO users VALUES (NULL, 'people\@allaround.com', 'passw0RD', datetime('now'));
	~);
}

sub task_clear{
	`rm log/* tmp/*`;
}

#initial setup: perl example.pl setup
#usage: lighttpd -f lighttpd.conf -D
#required modules: JSON::Any, HTML::Template, DBI, DBD::SQLite, Rose::DB::Object
#goto URLs:
#   http://0.0.0.0:3000/asdf/1234.json
#   http://0.0.0.0:3000/asdf/1234