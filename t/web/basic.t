#!/usr/bin/perl

use strict;
use RT::Test strict => 0, tests => 23, l10n => 1;
use HTTP::Request::Common;
use HTTP::Cookies;
use LWP;
use Encode;


my ($baseurl, $agent) = RT::Test->started_ok;
$agent->cookie_jar( HTTP::Cookies->new );

# get the top page
my $url = $agent->rt_base_url;
diag $url if $ENV{TEST_VERBOSE};
$agent->get($url);

is ($agent->{'status'}, 200, "Loaded a page");


# {{{ test a login

# follow the link marked "Login"
#
my $username = 'root';
my $password = "password";

            my $moniker = $agent->moniker_for('RT::Action::Login');

ok($moniker, "Found the moniker $moniker");

    ok( $agent->fill_in_action($moniker
            , username => $username, password => $password), "Filled in the login box");
$agent->submit();
is($agent->{'status'}, 200, "Fetched the page ok");
ok( $agent->content =~ /Logout/i, "Found a logout link");
$agent->get($url."/ticket/create?queue=1");
is ($agent->{'status'}, 200, "Loaded Create.html");
# Start with a string containing characters in latin1
my $string = "I18N Web Testing æøå";
my $decoded_string = Encode::decode_utf8($string);
$agent->fill_in_action_ok('create_ticket', (
    'subject' => "Ticket with utf8 body",
    'content' => $decoded_string,
));

ok($agent->submit(), "Created new ticket with $string as content");
like( $agent->{'content'}, qr{$string} , "Found the content");
ok($agent->{redirected_uri}, "Did redirection");

$agent->get($url."/ticket/create?queue=1");
is ($agent->{'status'}, 200, "Loaded Create.html");
$agent->fill_in_action_ok('create_ticket', (
    'subject' => $decoded_string,
    'content' => "Ticket with utf8 subject",
));
ok($agent->submit(), "Created new ticket with $string as subject");
like( $agent->{'content'}, qr{$string} , "Found the content");

# Update time worked in hours
$agent->follow_link( text_regex => qr/Basics/ );
my $basic_moniker = $agent->moniker_for('RT::Action::UpdateTicket');
$agent->fill_in_action_ok( $basic_moniker, 'time_worked' => '5h' );
$agent->submit;

    like ($agent->{'content'}, qr/to &#39;300&#39;/, "5 hours is 300 minutes");
# }}}

# {{{ test an image

TODO: {
    todo_skip("Need to handle mason trying to compile images",1);
$agent->get( $url."/static/images/test.png" );
my $file = RT::Test::get_relocatable_file(
  File::Spec->catfile(
    qw(.. .. share web static images test.png)
  )
);
is(
    length($agent->content),
    -s $file,
    "got a file of the correct size ($file)",
);
}
# }}}

    
# {{{ query Builder tests
#
# XXX: hey-ho, we have these tests in t/web/query-builder
# TODO: move everything about QB there

my $response = $agent->get($url."/Search/Build.html");
ok( $response->is_success, "Fetched " . $url."Search/Build.html" );

# Parsing TicketSQL
#
# Adding items

# set the first value
ok($agent->form_name('build_query'));
$agent->field("attachment_field", "subject");
$agent->field("attachment_op", "LIKE");
$agent->field("value_of_attachment", "aaa");
$agent->submit("AddClause");

# set the next value
ok($agent->form_name('build_query'));
$agent->field("attachment_field", "subject");
$agent->field("attachment_op", "LIKE");
$agent->field("value_of_attachment", "bbb");
$agent->submit("AddClause");
ok($agent->form_name('build_query'));

# get the query
my $query = $agent->current_form->find_input("query")->value;
# strip whitespace from ends
$query =~ s/^\s*//g;
$query =~ s/\s*$//g;

# collapse other whitespace
$query =~ s/\s+/ /g;

is ($query, "subject LIKE 'aaa' AND subject LIKE 'bbb'");

# - new items go one level down
# - add items at currently selected level
# - if nothing is selected, add at end, one level down
#
# move left
# - error if nothing selected
# - same item should be selected after move
# - can't move left if you're at the top level
#
# move right
# - error if nothing selected
# - same item should be selected after move
# - can always move right (no max depth...should there be?)
#
# move up
# - error if nothing selected
# - same item should be selected after move
# - can't move up if you're first in the list
#
# move down
# - error if nothing selected
# - same item should be selected after move
# - can't move down if you're last in the list
#
# toggle
# - error if nothing selected
# - change all aggregators in the grouping
# - don't change any others
#
# delete
# - error if nothing selected
# - delete currently selected item
# - delete all children of a grouping
# - if delete leaves a node with no children, delete that, too
# - what should be selected?
#
# Clear
# - clears entire query
# - clears it from the session, too

# }}}


1;
