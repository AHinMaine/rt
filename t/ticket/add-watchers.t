#!/usr/bin/perl -w
# BEGIN BPS TAGGED BLOCK {{{
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2005 Best Practical Solutions, LLC 
#                                          <jesse.com>
# 
# (Except where explicitly superseded by other copyright notices)
# 
# 
# LICENSE:
# 
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
# 
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
# 
# END BPS TAGGED BLOCK }}}

use Test::More tests => 32;
use RT::Test;

use strict;
use warnings;
no warnings 'once';

use RT::Model::Queue;
use RT::Model::User;
use RT::Model::Group;
use RT::Model::Ticket;
use RT::Model::ACE;
use RT::CurrentUser;


# clear all global right
my $acl = RT::Model::ACECollection->new(current_user => RT->system_user);
$acl->limit( column => 'right_name', operator => '!=', value => 'SuperUser' );
$acl->limit_to_object( RT->system );
while( my $ace = $acl->next ) {
	$ace->delete;
}

# create new queue to be sure we do not mess with rights
my $queue = RT::Model::Queue->new(current_user => RT->system_user);
my ($queue_id) = $queue->create( name =>  'watcher tests '.$$);
ok( $queue_id, 'queue created for watcher tests' );

# new privileged user to check rights
my $user = RT::Model::User->new(current_user => RT->system_user );
my ($user_id) = $user->create( name =>  'watcher'.$$,
			   email => "watcher$$".'@localhost',
			   privileged => 1,
			   password => 'qwe123',
			 );
my $cu= RT::CurrentUser->new( id => $user->id );

# make sure user can see tickets in the queue
my $principal = $user->principal;
ok( $principal, "principal loaded" );
$principal->grant_right( right => 'ShowTicket', object => $queue );
$principal->grant_right( right => 'SeeQueue'  , object => $queue );

ok(  $user->has_right( right => 'SeeQueue',     object => $queue ), "user can see queue" );
ok(  $user->has_right( right => 'ShowTicket',   object => $queue ), "user can show queue tickets" );
ok( !$user->has_right( right => 'ModifyTicket', object => $queue ), "user can't modify queue tickets" );
ok( !$user->has_right( right => 'Watch',        object => $queue ), "user can't watch queue tickets" );

my $ticket = RT::Model::Ticket->new(current_user => RT->system_user );
my ($rv, $msg) = $ticket->create( subject => 'watcher tests', queue => $queue->name );
ok( $ticket->id, "ticket created" );

my $ticket2 = RT::Model::Ticket->new(current_user => $cu );
$ticket2->load( $ticket->id );
ok( $ticket2->subject, "ticket load by user" );

# user can add self to ticket only after getting Watch right
($rv, $msg) = $ticket2->add_watcher( type => 'cc', principal => $user );
ok( !$rv, "user can't add self as Cc" );
($rv, $msg) = $ticket2->add_watcher( type => 'requestor', principal => $user );
ok( !$rv, "user can't add self as Requestor" );
$principal->grant_right( right => 'Watch'  , object => $queue );
ok(  $user->has_right( right => 'Watch',        object => $queue ), "user can watch queue tickets" );
($rv, $msg) = $ticket2->add_watcher( type => 'cc', principal => $user );
ok(  $rv, "user can add self as Cc by principal" );
($rv, $msg) = $ticket2->add_watcher( type => 'requestor', principal => $user );
ok(  $rv, "user can add self as Requestor by principal" );

# remove user and try adding with Email address
($rv, $msg) = $ticket->delete_watcher( type => 'cc',        principal => $user );
ok( $rv, "watcher removed by principal" );
($rv, $msg) = $ticket->delete_watcher( type => 'requestor', email => $user->email );
ok( $rv, "watcher removed by Email" );

($rv, $msg) = $ticket2->add_watcher( type => 'cc', email => $user->email );
ok(  $rv, "user can add self as Cc by Email" );
($rv, $msg) = $ticket2->add_watcher( type => 'requestor', email => $user->email );
ok(  $rv, "user can add self as Requestor by Email" );

# remove user and try adding by username
# This worked in 3.6 and is a regression in 3.8
($rv, $msg) = $ticket->delete_watcher( type => 'cc', email => $user->email );
ok( $rv, "watcher removed by email" );
($rv, $msg) = $ticket->delete_watcher( type => 'requestor', email => $user->email );
ok( $rv, "watcher removed by email" );

($rv, $msg) = $ticket2->add_watcher( type => 'cc', email => $user->name );
ok(  $rv, "user can add self as Cc by username" );
($rv, $msg) = $ticket2->add_watcher( type => 'requestor', email => $user->name );
ok(  $rv, "user can add self as Requestor by username" );

# Queue watcher tests
$principal->revoke_right( right => 'Watch'  , object => $queue );
ok( !$user->has_right( right => 'Watch',        object => $queue ), "user queue watch right revoked" );

my $queue2 = RT::Model::Queue->new( current_user => $cu );
($rv, $msg) = $queue2->load( $queue->id );
ok( $rv, "user loaded queue" );

# user can add self to queue only after getting Watch right
($rv, $msg) = $queue2->add_watcher( type => 'cc', principal => $user );
ok( !$rv, "user can't add self as Cc" );
($rv, $msg) = $queue2->add_watcher( type => 'requestor', principal => $user );
ok( !$rv, "user can't add self as Requestor" );
$principal->grant_right( right => 'Watch'  , object => $queue );
ok(  $user->has_right( right => 'Watch',        object => $queue ), "user can watch queue queues" );
($rv, $msg) = $queue2->add_watcher( type => 'cc', principal => $user );
ok(  $rv, "user can add self as Cc by principal" );
($rv, $msg) = $queue2->add_watcher( type => 'requestor', principal => $user );
ok(  $rv, "user can add self as Requestor by principal" );

# remove user and try adding with Email address
($rv, $msg) = $queue->delete_watcher( type => 'cc', principal => $user );
ok( $rv, "watcher removed by principal" );
($rv, $msg) = $queue->delete_watcher( type => 'requestor', email => $user->email );
ok( $rv, "watcher removed by Email" );

($rv, $msg) = $queue2->add_watcher( type => 'cc', email => $user->email );
ok(  $rv, "user can add self as Cc by Email" );
($rv, $msg) = $queue2->add_watcher( type => 'requestor', email => $user->email );
ok(  $rv, "user can add self as Requestor by Email" );

