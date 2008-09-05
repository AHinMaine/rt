#!/usr/bin/perl -w

use strict;
use warnings;

use RT::Test;
use Test::More tests => 119;

use RT::Model::Ticket;

my $q = RT::Test->load_or_create_queue( name => 'Regression' );
ok $q && $q->id, 'loaded or created queue';
my $queue = $q->name;

my ($total, @data, @tickets, %test) = (0, ());

sub add_tix_from_data {
    my @res = ();
    while (@data) {
        my $t = RT::Model::Ticket->new(current_user => RT->system_user);
        my ( $id, undef $msg ) = $t->create(
            queue => $q->id,
            %{ shift(@data) },
        );
        ok( $id, "ticket Created" ) or diag("error: $msg");
        push @res, $t;
        $total++;
    }
    return @res;
}

sub run_tests {
    my $query_prefix = join ' OR ', map 'id = '. $_->id, @tickets;
    foreach my $key ( sort keys %test ) {
        my $tix = RT::Model::TicketCollection->new(current_user => RT->system_user);
        $tix->from_sql( "( $query_prefix ) AND ( $key )" );

        my $error = 0;

        my $count = 0;
        $count++ foreach grep $_, values %{ $test{$key} };
        is($tix->count, $count, "found correct number of ticket(s) by '$key'") or $error = 1;

        my $good_tickets = ($tix->count == $count);
        while ( my $ticket = $tix->next ) {
            next if $test{$key}->{ $ticket->subject };
            diag $ticket->subject ." ticket has been found when it's not expected";
            $good_tickets = 0;
        }
        ok( $good_tickets, "all tickets are good with '$key'" ) or $error = 1;

        diag "Wrong SQL query for '$key':". $tix->build_select_query if $error;
    }
}

@data = (
    { subject => 'xy', requestor => ['x@example.com', 'y@example.com'] },
    { subject => 'x', requestor => 'x@example.com' },
    { subject => 'y', requestor => 'y@example.com' },
    { subject => '-', },
    { subject => 'z', requestor => 'z@example.com' },
);
%test = (
    'requestor = "x@example.com"'  => { xy => 1, x => 1, y => 0, '-' => 0, z => 0 },
    'requestor != "x@example.com"' => { xy => 0, x => 0, y => 1, '-' => 1, z => 1 },

    'requestor = "y@example.com"'  => { xy => 1, x => 0, y => 1, '-' => 0, z => 0 },
    'requestor != "y@example.com"' => { xy => 0, x => 1, y => 0, '-' => 1, z => 1 },

    'requestor LIKE "@example.com"'     => { xy => 1, x => 1, y => 1, '-' => 0, z => 1 },
    'requestor NOT LIKE "@example.com"' => { xy => 0, x => 0, y => 0, '-' => 1, z => 0 },

    'requestor IS NULL'            => { xy => 0, x => 0, y => 0, '-' => 1, z => 0 },
    'requestor IS NOT NULL'        => { xy => 1, x => 1, y => 1, '-' => 0, z => 1 },

# this test is a todo, we run it later
#    'requestor = "x@example.com" AND requestor = "y@example.com"'   => { xy => 1, x => 0, y => 0, '-' => 0, z => 0 },
    'requestor = "x@example.com" OR requestor = "y@example.com"'    => { xy => 1, x => 1, y => 1, '-' => 0, z => 0 },

    'requestor != "x@example.com" AND requestor != "y@example.com"' => { xy => 0, x => 0, y => 0, '-' => 1, z => 1 },
    'requestor != "x@example.com" OR requestor != "y@example.com"'  => { xy => 0, x => 1, y => 1, '-' => 1, z => 1 },

    'requestor = "x@example.com" AND requestor != "y@example.com"'  => { xy => 0, x => 1, y => 0, '-' => 0, z => 0 },
    'requestor = "x@example.com" OR requestor != "y@example.com"'   => { xy => 1, x => 1, y => 0, '-' => 1, z => 1 },

    'requestor != "x@example.com" AND requestor = "y@example.com"'  => { xy => 0, x => 0, y => 1, '-' => 0, z => 0 },
    'requestor != "x@example.com" OR requestor = "y@example.com"'   => { xy => 1, x => 0, y => 1, '-' => 1, z => 1 },
);
@tickets = add_tix_from_data();
{
    my $tix = RT::Model::TicketCollection->new(current_user => RT->system_user);
    $tix->from_sql("Queue = '$queue'");
    is($tix->count, $total, "found $total tickets");
}
run_tests();

# mixing searches by watchers with other conditions
# http://rt3.fsck.com/Ticket/Display.html?id=9322
%test = (
    'Subject LIKE "x" AND Requestor = "y@example.com"' =>
        { xy => 1, x => 0, y => 0, '-' => 0, z => 0 },
    'Subject NOT LIKE "x" AND Requestor = "y@example.com"' =>
        { xy => 0, x => 0, y => 1, '-' => 0, z => 0 },
    'Subject LIKE "x" AND Requestor != "y@example.com"' =>
        { xy => 0, x => 1, y => 0, '-' => 0, z => 0 },
    'Subject NOT LIKE "x" AND Requestor != "y@example.com"' =>
        { xy => 0, x => 0, y => 0, '-' => 1, z => 1 },

    'Subject LIKE "x" OR Requestor = "y@example.com"' =>
        { xy => 1, x => 1, y => 1, '-' => 0, z => 0 },
    'Subject NOT LIKE "x" OR Requestor = "y@example.com"' =>
        { xy => 1, x => 0, y => 1, '-' => 1, z => 1 },
    'Subject LIKE "x" OR Requestor != "y@example.com"' =>
        { xy => 1, x => 1, y => 0, '-' => 1, z => 1 },
    'Subject NOT LIKE "x" OR Requestor != "y@example.com"' =>
        { xy => 0, x => 1, y => 1, '-' => 1, z => 1 },

# group of cases when user doesn't exist in DB at all
    'Subject LIKE "x" AND Requestor = "not-exist@example.com"' =>
        { xy => 0, x => 0, y => 0, '-' => 0, z => 0 },
    'Subject NOT LIKE "x" AND Requestor = "not-exist@example.com"' =>
        { xy => 0, x => 0, y => 0, '-' => 0, z => 0 },
    'Subject LIKE "x" AND Requestor != "not-exist@example.com"' =>
        { xy => 1, x => 1, y => 0, '-' => 0, z => 0 },
    'Subject NOT LIKE "x" AND Requestor != "not-exist@example.com"' =>
        { xy => 0, x => 0, y => 1, '-' => 1, z => 1 },
#    'Subject LIKE "x" OR Requestor = "not-exist@example.com"' =>
#        { xy => 1, x => 1, y => 0, '-' => 0, z => 0 },
#    'Subject NOT LIKE "x" OR Requestor = "not-exist@example.com"' =>
#        { xy => 0, x => 0, y => 1, '-' => 1, z => 1 },
    'Subject LIKE "x" OR Requestor != "not-exist@example.com"' =>
        { xy => 1, x => 1, y => 1, '-' => 1, z => 1 },
    'Subject NOT LIKE "x" OR Requestor != "not-exist@example.com"' =>
        { xy => 1, x => 1, y => 1, '-' => 1, z => 1 },

    'Subject LIKE "z" AND (Requestor = "x@example.com" OR Requestor = "y@example.com")' =>
        { xy => 0, x => 0, y => 0, '-' => 0, z => 0 },
    'Subject NOT LIKE "z" AND (Requestor = "x@example.com" OR Requestor = "y@example.com")' =>
        { xy => 1, x => 1, y => 1, '-' => 0, z => 0 },
    'Subject LIKE "z" OR (Requestor = "x@example.com" OR Requestor = "y@example.com")' =>
        { xy => 1, x => 1, y => 1, '-' => 0, z => 1 },
    'Subject NOT LIKE "z" OR (Requestor = "x@example.com" OR Requestor = "y@example.com")' =>
        { xy => 1, x => 1, y => 1, '-' => 1, z => 0 },
);
run_tests();


TODO: {
    local $TODO = "we can't generate this query yet";
    %test = (
        'requestor = "x@example.com" AND requestor = "y@example.com"'
            => { xy => 1, x => 0, y => 0, '-' => 0, z => 0 },
        'subject LIKE "x" OR requestor = "not-exist@example.com"' =>
            { xy => 1, x => 1, y => 0, '-' => 0, z => 0 },
        'subject NOT LIKE "x" OR requestor = "not-exist@example.com"' =>
            { xy => 0, x => 0, y => 1, '-' => 1, z => 1 },
    );
    run_tests();
}

@data = (
    { subject => 'xy', cc => ['x@example.com'], requestor => [ 'y@example.com' ] },
    { subject => 'x-', cc => ['x@example.com'], requestor => [] },
    { subject => '-y', cc => [],                requestor => [ 'y@example.com' ] },
    { subject => '-', },
    { subject => 'zz', cc => ['z@example.com'], requestor => [ 'z@example.com' ] },
    { subject => 'z-', cc => ['z@example.com'], requestor => [] },
    { subject => '-z', cc => [],                requestor => [ 'z@example.com' ] },
);
%test = (
    'cc = "x@example.com" AND requestor = "y@example.com"' =>
        { xy => 1, 'x-' => 0, '-y' => 0, '-' => 0, zz => 0, 'z-' => 0, '-z' => 0 },
    'cc = "x@example.com" OR requestor = "y@example.com"' =>
        { xy => 1, 'x-' => 1, '-y' => 1, '-' => 0, zz => 0, 'z-' => 0, '-z' => 0 },

    'cc != "x@example.com" AND requestor = "y@example.com"' =>
        { xy => 0, 'x-' => 0, '-y' => 1, '-' => 0, zz => 0, 'z-' => 0, '-z' => 0 },
    'cc != "x@example.com" OR requestor = "y@example.com"' =>
        { xy => 1, 'x-' => 0, '-y' => 1, '-' => 1, zz => 1, 'z-' => 1, '-z' => 1 },

    'cc IS NULL AND requestor = "y@example.com"' =>
        { xy => 0, 'x-' => 0, '-y' => 1, '-' => 0, zz => 0, 'z-' => 0, '-z' => 0 },
    'cc IS NULL OR requestor = "y@example.com"' =>
        { xy => 1, 'x-' => 0, '-y' => 1, '-' => 1, zz => 0, 'z-' => 0, '-z' => 1 },

    'cc IS NOT NULL AND requestor = "y@example.com"' =>
        { xy => 1, 'x-' => 0, '-y' => 0, '-' => 0, zz => 0, 'z-' => 0, '-z' => 0 },
    'cc IS NOT NULL OR requestor = "y@example.com"' =>
        { xy => 1, 'x-' => 1, '-y' => 1, '-' => 0, zz => 1, 'z-' => 1, '-z' => 0 },
);
@tickets = add_tix_from_data();
{
    my $tix = RT::Model::TicketCollection->new(current_user => RT->system_user);
    $tix->from_sql("Queue = '$queue'");
    is($tix->count, $total, "found $total tickets");
}
run_tests();


# owner is special watcher because reference is duplicated in two places,
# owner was an ENUM field now it's WATCHERFIELD, but should support old
# style ENUM searches for backward compatibility
my $nobody = RT->nobody();
{
    my $tix = RT::Model::TicketCollection->new(current_user => RT->system_user);
    $tix->from_sql("Queue = '$queue' AND Owner = '". $nobody->id ."'");
    ok($tix->count, "found ticket(s)");
}
{
    my $tix = RT::Model::TicketCollection->new(current_user => RT->system_user);
    $tix->from_sql("Queue = '$queue' AND Owner = '". $nobody->name ."'");
    ok($tix->count, "found ticket(s)");
}
{
    my $tix = RT::Model::TicketCollection->new(current_user => RT->system_user);
    $tix->from_sql("Queue = '$queue' AND Owner != '". $nobody->id ."'");
    is($tix->count, 0, "found ticket(s)");
}
{
    my $tix = RT::Model::TicketCollection->new(current_user => RT->system_user);
    $tix->from_sql("Queue = '$queue' AND Owner != '". $nobody->name ."'");
    is($tix->count, 0, "found ticket(s)");
}

{
    my $tix = RT::Model::TicketCollection->new(current_user => RT->system_user);
    $tix->from_sql("Queue = '$queue' AND Owner.name LIKE 'nob'");
    ok($tix->count, "found ticket(s)");
}

{
    # create ticket and force type to not a 'ticket' value
    # bug #6898@rt3.fsck.com
    # and http://marc.theaimsgroup.com/?l=rt-devel&m=112662934627236&w=2
    @data = ( { subject => 'not a ticket' } );
    my($t) = add_tix_from_data();
    $t->_set( column             => 'type',
              value             => 'not a ticket',
              check_acl          => 0,
              record_transaction => 0,
            );
    $total--;

    my $tix = RT::Model::TicketCollection->new(current_user => RT->system_user);
    $tix->from_sql("Queue = '$queue' AND Owner = 'Nobody'");
    is($tix->count, $total, "found ticket(s)");
}

{
    my $everyone = RT::Model::Group->new(current_user => RT->system_user );
    $everyone->load_system_internal_group('Everyone');
    ok($everyone->id, "loaded 'everyone' group");
    my($id, $msg) = $everyone->principal->grant_right( right => 'OwnTicket',
                                                         object => $q
                                                       );
    ok($id, "granted OwnTicket right to Everyone on '$queue'") or diag("error: $msg");

    my $u = RT::Model::User->new(current_user => RT->system_user );
    $u->load_or_create_by_email('alpha@example.com');
    ok($u->id, "loaded user");
    @data = ( { subject => '4', owner => $u->id } );
    my($t) = add_tix_from_data();
    is( $t->owner, $u->id, "Created ticket with custom owner" );
    my $u_alpha_id = $u->id;

    $u = RT::Model::User->new(current_user => RT->system_user );
    $u->load_or_create_by_email('bravo@example.com');
    ok($u->id, "loaded user");
    @data = ( { subject => '5', owner => $u->id } );
    ($t) = add_tix_from_data();
    is( $t->owner, $u->id, "Created ticket with custom owner" );
    my $u_bravo_id = $u->id;

    my $tix = RT::Model::TicketCollection->new(current_user => RT->system_user);
    $tix->from_sql("Queue = '$queue' AND
                   ( Owner = '$u_alpha_id' OR
                     Owner = '$u_bravo_id' )"
                 );
    is($tix->count, 2, "found ticket(s)");
}


exit(0)
