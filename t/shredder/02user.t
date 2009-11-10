#!/usr/bin/perl -w

use strict;
use warnings;

use RT::Test strict => 1; use Test::More;
use Test::Deep;
use File::Spec;
use RT::Test::Shredder;
RT::Test::Shredder::init_db();

plan tests => 8;

RT::Test::Shredder::create_savepoint('clean');

my $queue = RT::Model::Queue->new(current_user => RT->system_user );
my ($qid) = $queue->load( 'General' );
ok( $qid, "loaded queue" );

my $ticket = RT::Model::Ticket->new(current_user => RT->system_user );
my ($tid) = $ticket->create( queue => $qid, subject => 'test' );
ok( $tid, "ticket Created" );

RT::Test::Shredder::create_savepoint('bucreate'); # berfore user create
my $user = RT::Model::User->new(current_user => RT->system_user );
my ($uid, $msg) = $user->create( name => 'new user', privileged => 1, disabled => 0 );
ok( $uid, "Created new user" ) or diag "error: $msg";
is( $user->id, $uid, "id is correct" );
# HACK: set ticket props to enable VARIABLE dependencies
$ticket->__set( column => 'last_updated_by', value => $uid );
RT::Test::Shredder::create_savepoint('aucreate'); # after user create

{
    my $resolver = sub  {
        my %args = (@_);
        my $t =	$args{'target_object'};
        my $resolver_uid = RT->system_user->id;
        foreach my $method ( qw(creator last_updated_by) ) {
            next unless $t->can($method);
            $t->__set( column => $method, value => $resolver_uid );
        }
    };
    my $shredder = RT::Test::Shredder::shredder_new();
    $shredder->put_resolver( base_class => 'RT::Model::User', code => $resolver );
    $shredder->wipeout( object => $user );
    cmp_deeply( RT::Test::Shredder::dump_current_and_savepoint('bucreate'), "current DB equal to savepoint");
}

{
    RT::Test::Shredder::restore_savepoint('aucreate');
    my $user = RT::Model::User->new(current_user => RT->system_user );
    $user->load($uid);
    ok($user->id, "loaded user after restore");
    my $shredder = RT::Test::Shredder::shredder_new();
    eval { $shredder->wipeout( object => $user ) };
    ok($@, "wipeout throw exception if no resolvers");
    cmp_deeply( RT::Test::Shredder::dump_current_and_savepoint('aucreate'), "current DB equal to savepoint");
}
