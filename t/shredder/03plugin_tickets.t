#!/usr/bin/perl -w

use strict;
use warnings;

use RT::Test; use Test::More;
use Test::Deep;
use File::Spec;
use RT::Test::Shredder;

plan tests => 44;

use_ok('RT::Shredder::Plugin::Tickets');
{
    my $plugin = RT::Shredder::Plugin::Tickets->new;
    isa_ok($plugin, 'RT::Shredder::Plugin::Tickets');

    is(lc $plugin->type, 'search', 'correct type');
}

RT::Test::Shredder::init_db();
RT::Test::Shredder::create_savepoint('clean');
use_ok('RT::Model::Ticket');
use_ok('RT::Model::TicketCollection');

{ # create parent and child and check functionality of 'with_linked' arg
    my $parent = RT::Model::Ticket->new(current_user => RT->system_user );
    my ($pid) = $parent->create( subject => 'parent', queue => 1 );
    ok( $pid, "Created new ticket" );

    my $child = RT::Model::Ticket->new(current_user => RT->system_user );
    my ($cid) = $child->create( subject => 'child', queue => 1, MemberOf => $pid );
    ok( $cid, "Created new ticket" );

    my $plugin = RT::Shredder::Plugin::Tickets->new;
    isa_ok($plugin, 'RT::Shredder::Plugin::Tickets');

    my ($status, $msg, @objs);
    ($status, $msg) = $plugin->test_args( query => 'subject = "parent"' );
    ok($status, "plugin arguments are ok") or diag "error: $msg";

    ($status, @objs) = $plugin->run;
    ok($status, "executed plugin successfully") or diag "error: @objs";
    @objs = RT::Shredder->cast_objects_to_records( objects => \@objs );
    is(scalar @objs, 1, "only one object in result set");
    is($objs[0]->id, $pid, "parent is in result set");

    ($status, $msg) = $plugin->test_args( query => 'subject = "parent"', with_linked => 1 );
    ok($status, "plugin arguments are ok") or diag "error: $msg";

    ($status, @objs) = $plugin->run;
    ok($status, "executed plugin successfully") or diag "error: @objs";
    @objs = RT::Shredder->cast_objects_to_records( objects => \@objs );
    my %has = map { $_->id => 1 } @objs;
    is(scalar @objs, 2, "two objects in the result set");
    ok($has{$pid}, "parent is in the result set");
    ok($has{$cid}, "child is in the result set");

    my $shredder = RT::Test::Shredder::shredder_new();
    $shredder->put_objects( objects => \@objs );
    $shredder->wipeout_all;
}
cmp_deeply( RT::Test::Shredder::dump_current_and_savepoint('clean'), "current DB equal to savepoint");

{ # create parent and child and link them reqursively to check that we don't hang
    my $parent = RT::Model::Ticket->new(current_user => RT->system_user );
    my ($pid) = $parent->create( subject => 'parent', queue => 1 );
    ok( $pid, "Created new ticket" );

    my $child = RT::Model::Ticket->new(current_user => RT->system_user );
    my ($cid) = $child->create( subject => 'child', queue => 1, MemberOf => $pid );
    ok( $cid, "Created new ticket" );

    my ($status, $msg) = $child->add_link( target => $pid, type => 'DependsOn' );
    ok($status, "added reqursive link") or diag "error: $msg";

    my $plugin = RT::Shredder::Plugin::Tickets->new;
    isa_ok($plugin, 'RT::Shredder::Plugin::Tickets');

    my (@objs);
    ($status, $msg) = $plugin->test_args( query => 'subject = "parent"' );
    ok($status, "plugin arguments are ok") or diag "error: $msg";

    ($status, @objs) = $plugin->run;
    ok($status, "executed plugin successfully") or diag "error: @objs";
    @objs = RT::Shredder->cast_objects_to_records( objects => \@objs );
    is(scalar @objs, 1, "only one object in result set");
    is($objs[0]->id, $pid, "parent is in result set");

    ($status, $msg) = $plugin->test_args( query => 'subject = "parent"', with_linked => 1 );
    ok($status, "plugin arguments are ok") or diag "error: $msg";

    ($status, @objs) = $plugin->run;
    ok($status, "executed plugin successfully") or diag "error: @objs";
    @objs = RT::Shredder->cast_objects_to_records( objects => \@objs );
    is(scalar @objs, 2, "two objects in the result set");
    my %has = map { $_->id => 1 } @objs;
    ok($has{$pid}, "parent is in the result set");
    ok($has{$cid}, "child is in the result set");

    my $shredder = RT::Test::Shredder::shredder_new();
    $shredder->put_objects( objects => \@objs );
    $shredder->wipeout_all;
}
cmp_deeply( RT::Test::Shredder::dump_current_and_savepoint('clean'), "current DB equal to savepoint");

{ # create parent and child and check functionality of 'apply_query_to_linked' arg
    my $parent = RT::Model::Ticket->new(current_user => RT->system_user );
    my ($pid) = $parent->create( subject => 'parent', queue => 1, status => 'resolved' );
    ok( $pid, "Created new ticket" );

    my $child1 = RT::Model::Ticket->new(current_user => RT->system_user );
    my ($cid1) = $child1->create( subject => 'child', queue => 1, MemberOf => $pid );
    ok( $cid1, "Created new ticket" );
    my $child2 = RT::Model::Ticket->new(current_user => RT->system_user );
    my ($cid2) = $child2->create( subject => 'child', queue => 1, MemberOf => $pid, status => 'resolved' );
    ok( $cid2, "Created new ticket" );

    my $plugin = RT::Shredder::Plugin::Tickets->new;
    isa_ok($plugin, 'RT::Shredder::Plugin::Tickets');

    my ($status, $msg) = $plugin->test_args( query => 'Status = "resolved"', apply_query_to_linked => 1 );
    ok($status, "plugin arguments are ok") or diag "error: $msg";

    my @objs;
    ($status, @objs) = $plugin->run;
    ok($status, "executed plugin successfully") or diag "error: @objs";
    @objs = RT::Shredder->cast_objects_to_records( objects => \@objs );
    is(scalar @objs, 2, "two objects in the result set");
    my %has = map { $_->id => 1 } @objs;
    ok($has{$pid}, "parent is in the result set");
    ok(!$has{$cid1}, "first child is in the result set");
    ok($has{$cid2}, "second child is in the result set");

    my $shredder = RT::Test::Shredder::shredder_new();
    $shredder->put_objects( objects => \@objs );
    $shredder->wipeout_all;

    my $ticket = RT::Model::Ticket->new(current_user => RT->system_user );
    $ticket->load( $cid1 );
    is($ticket->id, $cid1, 'loaded ticket');

    $shredder->put_objects( objects => $ticket );
    $shredder->wipeout_all;
}
cmp_deeply( RT::Test::Shredder::dump_current_and_savepoint('clean'), "current DB equal to savepoint");
