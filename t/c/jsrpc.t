#!/usr/bin/perl -w
use Test::More tests => 5;

BEGIN {
    $ENV{CATALYST_CONFIG} = 't/var/mojomojo.yml';
}
use_ok( Catalyst::Test, 'MojoMojo' );
use_ok('MojoMojo::Controller::Jsrpc');

my $req = request('/.jsrpc/render?content=123');
ok( $req->is_success );
# Need to remove end of line character from content for comparsion.
my $content = $req->content;
chomp $content;
is( $content, '<p>123</p>', 'correct body returned' );
ok( request('/.jsrpc/child_menu')->is_success );
