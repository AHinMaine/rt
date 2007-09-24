
use strict;
use warnings;
use RT::Test; use Test::More; 
plan tests => 4;
use RT;



{
    undef $main::_STDOUT_;
    undef $main::_STDERR_;

ok(require RT::EmailParser);


    undef $main::_STDOUT_;
    undef $main::_STDERR_;
}

{
    undef $main::_STDOUT_;
    undef $main::_STDERR_;

is(RT::EmailParser::IsRTAddress("","rt\@example.com"),1, "Regexp matched rt address" );
is(RT::EmailParser::IsRTAddress("","frt\@example.com"),undef, "Regexp didn't match non-rt address" );


    undef $main::_STDOUT_;
    undef $main::_STDERR_;
}

{
    undef $main::_STDOUT_;
    undef $main::_STDERR_;

my @before = ("rt\@example.com", "frt\@example.com");
my @after = ("frt\@example.com");
ok(eq_array(RT::EmailParser::CullRTAddresses("",@before),@after), "CullRTAddresses only culls RT addresses");


    undef $main::_STDOUT_;
    undef $main::_STDERR_;
}

1;
