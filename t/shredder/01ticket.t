
use strict;
use warnings;

use Test::Deep;
use RT::Test::Shredder tests => 15;
my $test = "RT::Test::Shredder";

$test->create_savepoint('clean');

use RT::Ticket;
use RT::Tickets;

{
    my $ticket = RT::Ticket->new( RT->SystemUser );
    my ($id) = $ticket->Create( Subject => 'test', Queue => 1 );
    ok( $id, "created new ticket" );
    $ticket->Delete;
    is( $ticket->Status, 'deleted', "successfuly changed status" );

    my $tickets = RT::Tickets->new( RT->SystemUser );
    $tickets->{'allow_deleted_search'} = 1;
    $tickets->LimitStatus( VALUE => 'deleted' );
    is( $tickets->Count, 1, "found one deleted ticket" );

    my $shredder = $test->shredder_new();
    $shredder->PutObjects( Objects => $tickets );
    $shredder->WipeoutAll;
}
cmp_deeply( $test->dump_current_and_savepoint('clean'), "current DB equal to savepoint");

{
    my $parent = RT::Ticket->new( RT->SystemUser );
    my ($pid) = $parent->Create( Subject => 'test', Queue => 1 );
    ok( $pid, "created new ticket" );
    $test->create_savepoint('parent_ticket');

    my $child = RT::Ticket->new( RT->SystemUser );
    my ($cid) = $child->Create( Subject => 'test', Queue => 1 );
    ok( $cid, "created new ticket" );

    my ($status, $msg) = $parent->AddLink( Type => 'MemberOf', Target => $cid );
    ok( $status, "Added link between tickets") or diag("error: $msg");
    my $shredder = $test->shredder_new();
    $shredder->PutObjects( Objects => $child );
    $shredder->WipeoutAll;
    cmp_deeply( $test->dump_current_and_savepoint('parent_ticket'), "current DB equal to savepoint");

    $shredder->PutObjects( Objects => $parent );
    $shredder->WipeoutAll;
}
cmp_deeply( $test->dump_current_and_savepoint('clean'), "current DB equal to savepoint");

{
    my $parent = RT::Ticket->new( RT->SystemUser );
    my ($pid) = $parent->Create( Subject => 'test', Queue => 1 );
    ok( $pid, "created new ticket" );
    my ($status, $msg) = $parent->Delete;
    ok( $status, 'deleted parent ticket');
    $test->create_savepoint('parent_ticket');

    my $child = RT::Ticket->new( RT->SystemUser );
    my ($cid) = $child->Create( Subject => 'test', Queue => 1 );
    ok( $cid, "created new ticket" );

    ($status, $msg) = $parent->AddLink( Type => 'DependsOn', Target => $cid );
    ok( $status, "Added link between tickets") or diag("error: $msg");
    my $shredder = $test->shredder_new();
    $shredder->PutObjects( Objects => $child );
    $shredder->WipeoutAll;
    cmp_deeply( $test->dump_current_and_savepoint('parent_ticket'), "current DB equal to savepoint");

    $shredder->PutObjects( Objects => $parent );
    $shredder->WipeoutAll;
}
cmp_deeply( $test->dump_current_and_savepoint('clean'), "current DB equal to savepoint");
