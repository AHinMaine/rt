#!/usr/bin/perl -w

use strict;
use warnings;

use RT::Test; use Test::More;
use Test::Deep;
BEGIN { require "t/shredder/utils.pl"; }

plan tests => 44;

use_ok('RT::Shredder::Plugin::Tickets');
{
    my $plugin = new RT::Shredder::Plugin::Tickets;
    isa_ok($plugin, 'RT::Shredder::Plugin::Tickets');

    is(lc $plugin->Type, 'search', 'correct type');
}

init_db();
create_savepoint('clean');
use_ok('RT::Model::Ticket');
use_ok('RT::Model::TicketCollection');

{ # create parent and child and check functionality of 'with_linked' arg
    my $parent = RT::Model::Ticket->new( RT->SystemUser );
    my ($pid) = $parent->create( Subject => 'parent', Queue => 1 );
    ok( $pid, "Created new ticket" );

    my $child = RT::Model::Ticket->new( RT->SystemUser );
    my ($cid) = $child->create( Subject => 'child', Queue => 1, MemberOf => $pid );
    ok( $cid, "Created new ticket" );

    my $plugin = new RT::Shredder::Plugin::Tickets;
    isa_ok($plugin, 'RT::Shredder::Plugin::Tickets');

    my ($status, $msg, @objs);
    ($status, $msg) = $plugin->TestArgs( query => 'Subject = "parent"' );
    ok($status, "plugin arguments are ok") or diag "error: $msg";

    ($status, @objs) = $plugin->Run;
    ok($status, "executed plugin successfully") or diag "error: @objs";
    @objs = RT::Shredder->CastObjectsToRecords( Objects => \@objs );
    is(scalar @objs, 1, "only one object in result set");
    is($objs[0]->id, $pid, "parent is in result set");

    ($status, $msg) = $plugin->TestArgs( query => 'Subject = "parent"', with_linked => 1 );
    ok($status, "plugin arguments are ok") or diag "error: $msg";

    ($status, @objs) = $plugin->Run;
    ok($status, "executed plugin successfully") or diag "error: @objs";
    @objs = RT::Shredder->CastObjectsToRecords( Objects => \@objs );
    my %has = map { $_->id => 1 } @objs;
    is(scalar @objs, 2, "two objects in the result set");
    ok($has{$pid}, "parent is in the result set");
    ok($has{$cid}, "child is in the result set");

    my $shredder = shredder_new();
    $shredder->PutObjects( Objects => \@objs );
    $shredder->WipeoutAll;
}
cmp_deeply( dump_current_and_savepoint('clean'), "current DB equal to savepoint");

{ # create parent and child and link them reqursively to check that we don't hang
    my $parent = RT::Model::Ticket->new( RT->SystemUser );
    my ($pid) = $parent->create( Subject => 'parent', Queue => 1 );
    ok( $pid, "Created new ticket" );

    my $child = RT::Model::Ticket->new( RT->SystemUser );
    my ($cid) = $child->create( Subject => 'child', Queue => 1, MemberOf => $pid );
    ok( $cid, "Created new ticket" );

    my ($status, $msg) = $child->AddLink( Target => $pid, Type => 'DependsOn' );
    ok($status, "added reqursive link") or diag "error: $msg";

    my $plugin = new RT::Shredder::Plugin::Tickets;
    isa_ok($plugin, 'RT::Shredder::Plugin::Tickets');

    my (@objs);
    ($status, $msg) = $plugin->TestArgs( query => 'Subject = "parent"' );
    ok($status, "plugin arguments are ok") or diag "error: $msg";

    ($status, @objs) = $plugin->Run;
    ok($status, "executed plugin successfully") or diag "error: @objs";
    @objs = RT::Shredder->CastObjectsToRecords( Objects => \@objs );
    is(scalar @objs, 1, "only one object in result set");
    is($objs[0]->id, $pid, "parent is in result set");

    ($status, $msg) = $plugin->TestArgs( query => 'Subject = "parent"', with_linked => 1 );
    ok($status, "plugin arguments are ok") or diag "error: $msg";

    ($status, @objs) = $plugin->Run;
    ok($status, "executed plugin successfully") or diag "error: @objs";
    @objs = RT::Shredder->CastObjectsToRecords( Objects => \@objs );
    is(scalar @objs, 2, "two objects in the result set");
    my %has = map { $_->id => 1 } @objs;
    ok($has{$pid}, "parent is in the result set");
    ok($has{$cid}, "child is in the result set");

    my $shredder = shredder_new();
    $shredder->PutObjects( Objects => \@objs );
    $shredder->WipeoutAll;
}
cmp_deeply( dump_current_and_savepoint('clean'), "current DB equal to savepoint");

{ # create parent and child and check functionality of 'apply_query_to_linked' arg
    my $parent = RT::Model::Ticket->new( RT->SystemUser );
    my ($pid) = $parent->create( Subject => 'parent', Queue => 1, Status => 'resolved' );
    ok( $pid, "Created new ticket" );

    my $child1 = RT::Model::Ticket->new( RT->SystemUser );
    my ($cid1) = $child1->create( Subject => 'child', Queue => 1, MemberOf => $pid );
    ok( $cid1, "Created new ticket" );
    my $child2 = RT::Model::Ticket->new( RT->SystemUser );
    my ($cid2) = $child2->create( Subject => 'child', Queue => 1, MemberOf => $pid, Status => 'resolved' );
    ok( $cid2, "Created new ticket" );

    my $plugin = new RT::Shredder::Plugin::Tickets;
    isa_ok($plugin, 'RT::Shredder::Plugin::Tickets');

    my ($status, $msg) = $plugin->TestArgs( query => 'Status = "resolved"', apply_query_to_linked => 1 );
    ok($status, "plugin arguments are ok") or diag "error: $msg";

    my @objs;
    ($status, @objs) = $plugin->Run;
    ok($status, "executed plugin successfully") or diag "error: @objs";
    @objs = RT::Shredder->CastObjectsToRecords( Objects => \@objs );
    is(scalar @objs, 2, "two objects in the result set");
    my %has = map { $_->id => 1 } @objs;
    ok($has{$pid}, "parent is in the result set");
    ok(!$has{$cid1}, "first child is in the result set");
    ok($has{$cid2}, "second child is in the result set");

    my $shredder = shredder_new();
    $shredder->PutObjects( Objects => \@objs );
    $shredder->WipeoutAll;

    my $ticket = RT::Model::Ticket->new( RT->SystemUser );
    $ticket->load( $cid1 );
    is($ticket->id, $cid1, 'loaded ticket');

    $shredder->PutObjects( Objects => $ticket );
    $shredder->WipeoutAll;
}
cmp_deeply( dump_current_and_savepoint('clean'), "current DB equal to savepoint");

