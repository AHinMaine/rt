#!/usr/bin/perl

use strict;
use RT::Test; use Test::More;
plan tests => 387;
use HTTP::Request::Common;
use HTTP::Cookies;
use LWP;
use Encode;

my $cookie_jar = HTTP::Cookies->new;


my ($baseurl, $agent) = RT::Test->started_ok;

# give the agent a place to stash the cookies
$agent->cookie_jar($cookie_jar);

# get the top page
my $url = $agent->rt_base_url;
diag "Base URL is '$url'" if $ENV{TEST_VERBOSE};
$agent->get($url);

is ($agent->{'status'}, 200, "Loaded a page");

# {{{ test a login

# follow the link marked "Login"

ok($agent->{form}->find_input('user'));

ok($agent->{form}->find_input('pass'));
like ($agent->{'content'} , qr/username:/i);
$agent->field( 'user' => 'root' );
$agent->field( 'pass' => 'password' );
# the field isn't named, so we have to click link 0
$agent->click(0);
is($agent->{'status'}, 200, "Fetched the page ok");
like( $agent->{'content'} , qr/Logout/i, "Found a logout link");


use File::Find;
find ( \&wanted , 'html/');

sub wanted {
        -f  && /\.html$/ && $_ !~ /Logout.html$/ && test_get($File::Find::name);
}       

sub test_get {
        my $file = shift;

        $file =~ s#^html/##;
        diag( "testing $url/$file" ) if $ENV{TEST_VERBOSE};
        ok ($agent->get("$url/$file", "GET $url/$file"), "Can Get $url/$file");
        is ($agent->{'status'}, 200, "Loaded $file");
#        ok( $agent->{'content'} =~ /Logout/i, "Found a logout link on $file ");
        ok( $agent->{'content'} !~ /Not logged in/i, "Still logged in for  $file");
        ok( $agent->{'content'} !~ /raw error/i, "Didn't get a Mason compilation error on $file");
}

# }}}

1;
