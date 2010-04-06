#!/usr/bin/perl

use strict;
use RT::Test strict => 1; use Test::More tests => 42;
use HTTP::Request::Common;
use HTTP::Cookies;
use LWP;
use Encode;


my $cookie_jar = HTTP::Cookies->new;
my ($baseurl, $agent) = RT::Test->started_ok;


# give the agent a place to stash the cookies

$agent->cookie_jar($cookie_jar);

# create a regression queue if it doesn't exist
my $queue = RT::Test->load_or_create_queue( name => 'Regression' );
ok $queue && $queue->id, 'loaded or Created queue';

my $url = $agent->rt_base_url;
ok $agent->login, "logged in";

# {{{ Query Builder tests

$agent->get_ok($url."/Search/Build.html");

sub get_query_from_form {
    $agent->form_name('build_query');
    # This pulls out the "hidden input" query from the page
    my $q = $agent->current_form->find_input("query")->value;
    $q =~ s/^\s+//g;
    $q =~ s/\s+$//g;
    $q =~ s/\s+/ /g;
    return $q;
}

sub selected_clauses {
    my @clauses = grep { defined } map { $_->value } $agent->current_form->find_input("clauses");
    return [ @clauses ];
}


diag "add the first condition" if $ENV{'TEST_VERBOSE'};
{
    ok $agent->form_name('build_query'), "found the form once";
    $agent->field("actor_field", "owner");
    $agent->field("actor_op", "=");
    $agent->field("value_of_actor", 'Nobody');
    $agent->submit;
    is lc get_query_from_form, lc "Owner = 'Nobody'", 'correct query';
}

diag "set the next condition" if $ENV{'TEST_VERBOSE'};
{
    ok($agent->form_name('build_query'), "found the form again");
    $agent->field("queue_op", "!=");
    $agent->field("value_of_queue", "Regression");
    $agent->submit;
    is get_query_from_form, "owner = 'Nobody' AND queue != 'Regression'",
        'correct query';
}

diag "We're going to delete the owner" if $ENV{'TEST_VERBOSE'};
{
    $agent->select("clauses", ["0"] );
    $agent->click("delete_clause");
    ok $agent->form_name('build_query'), "found the form";
    is get_query_from_form, "queue != 'Regression'", 'correct query';
}

diag "add a cond with OR and se number by the way" if $ENV{'TEST_VERBOSE'};
{
    $agent->field("and_or", "OR");
    $agent->select("id_op", ">");
    $agent->field("value_of_id" => "1234");
    $agent->click("add_clause");
    ok $agent->form_name('build_query'), "found the form again";
    is get_query_from_form, "queue != 'Regression' OR id > 1234",
        "added something as OR, and number not quoted";
    is_deeply selected_clauses, ["1"], 'the id that we just entered is still selected';

}

diag "Move the second one up a level" if $ENV{'TEST_VERBOSE'};
{
    $agent->click("up");
    ok $agent->form_name('build_query'), "found the form again";
    is get_query_from_form, "id > 1234 OR queue != 'Regression'", "moved up one";
    is_deeply selected_clauses, ["0"], 'the one we moved up is selected';
}

diag "Move the second one right" if $ENV{'TEST_VERBOSE'};
{
    $agent->click("right");
    ok $agent->form_name('build_query'), "found the form again";
    is get_query_from_form, "queue != 'Regression' OR ( id > 1234 )",
        "moved over to the right (and down)";
    is_deeply selected_clauses, ["2"], 'the one we moved right is selected';
}

diag "Move the block up" if $ENV{'TEST_VERBOSE'};
{
    $agent->select("clauses", ["1"]);
    $agent->click("up");
    ok $agent->form_name('build_query'), "found the form again";
    is get_query_from_form, "( id > 1234 ) OR queue != 'Regression'", "moved up";
    is_deeply selected_clauses, ["0"], 'the one we moved up is selected';
}


diag "Can not move up the top most clause" if $ENV{'TEST_VERBOSE'};
{
    $agent->select("clauses", ["0"]);
    $agent->click("up");
    ok $agent->form_name('build_query'), "found the form again";
    $agent->content_like(qr/error: can\S+t move up/, "i shouldn't have been able to hit up");
    is_deeply selected_clauses, ["0"], 'the one we tried to move is selected';
}

diag "Can not move left the left most clause" if $ENV{'TEST_VERBOSE'};
{
    $agent->click("left");
    ok($agent->form_name('build_query'), "found the form again");
    $agent->content_like(qr/error: can\S+t move left/, "i shouldn't have been able to hit left");
    is_deeply selected_clauses, ["0"], 'the one we tried to move is selected';
}

diag "Add a condition into a nested block" if $ENV{'TEST_VERBOSE'};
{
    $agent->select("clauses", ["1"]);
    $agent->select("value_of_status" => "stalled");
    $agent->submit;
    ok $agent->form_name('build_query'), "found the form again";
    is_deeply selected_clauses, ["2"], 'the one we added is only selected';
    is get_query_from_form,
        "( id > 1234 AND status = 'stalled' ) OR queue != 'Regression'",
        "added new one";
}

diag "click advanced, enter 'C1 OR ( C2 AND C3 )', apply, aggregators should stay the same."
    if $ENV{'TEST_VERBOSE'};
{
    $agent->get_ok($url."/Search/Edit.html");
    ok($agent->form_name('query_edit'), "found the form");
    $agent->field("query", "Status = 'new' OR ( Status = 'open' AND subject LIKE 'office' )");
    $agent->submit;
    is( get_query_from_form,
        "status = 'new' OR ( status = 'open' AND subject LIKE 'office' )",
        "no aggregators change"
    );
}

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

# create a custom field with nonascii name and try to add a condition


    my $cf = RT::Model::CustomField->new(current_user => RT->system_user );
    $cf->load_by_name( name => "\x{442}", queue => 0 );
    if ( $cf->id ) {
        is($cf->type, 'Freeform', 'loaded and type is correct');
    } else {
        my ($return, $msg) = $cf->create(
            name => "\x{442}",
            queue => 0,
            type => 'Freeform',
        );
        ok($return, 'Created CF') or diag "error: $msg";
    }
    $agent->get_ok($url."/Search/Build.html?new_query=1");

    ok($agent->form_name('build_query'), "found the form once");
    $agent->field("ValueOf'CF.{\x{442}}'", "\x{441}");
    
    $agent->submit();
TODO: {
   local $TODO = "4.0 custom fields with non-ascii names currently explode. note sure why.";
    is( get_query_from_form,
        "'CF.{\x{442}}' LIKE '\x{441}'",
        "no changes, no duplicate condition with badly encoded text"
    );


};

diag "input a condition, select (several conditions), click delete"
    if $ENV{'TEST_VERBOSE'};
{
    $agent->get_ok( $url."/Search/Edit.html" );
    ok $agent->form_name('query_edit'), "found the form";
    $agent->field("query", "( Status = 'new' OR Status = 'open' )");
    $agent->submit;
    is( get_query_from_form,
        "( status = 'new' OR status = 'open' )",
        "query is the same"
    );
    $agent->select("clauses", [qw(0 1 2)]);
    $agent->field( value_of_id => 10 );
    $agent->click("delete_clause");

    is( get_query_from_form,
        "id < 10",
        "replaced query successfuly"
    );
}

1;
