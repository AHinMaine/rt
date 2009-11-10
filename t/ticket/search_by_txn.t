#!/usr/bin/perl

use warnings;
use strict;

use RT::Test strict => 1; use Test::More tests => 11;

BEGIN{ $ENV{'TZ'} = 'GMT'};



my $SUBJECT = "Search test - ".$$;

use_ok('RT::Model::TicketCollection');
my $tix = RT::Model::TicketCollection->new(current_user => RT->system_user);
can_ok($tix, 'from_sql');
$tix->from_sql('Updated = "2005-08-05" AND subject = "$SUBJECT"');

ok(! $tix->count, "Searching for tickets updated on a random date finds nothing" . $tix->count);

my $ticket = RT::Model::Ticket->new(current_user => RT->system_user);
my ($id, $tid,$msg) = $ticket->create(queue => 'General', subject => $SUBJECT);
ok($id,$msg);
ok ($ticket->id, "We Created a ticket");
my ($commentid, $txnid, $txnobj) =  $ticket->comment( content => 'A comment that happend on 2004-01-01');

isa_ok($txnobj, 'RT::Model::Transaction');

ok($txnobj->created->iso);
my ( $sid,$smsg) = $txnobj->__set(column => 'created', value => '2005-08-05 20:00:56');
ok($sid,$smsg);
is($txnobj->created,'2005-08-05 20:00:56');
is($txnobj->created->iso,'2005-08-05 20:00:56');

$tix->from_sql(qq{Updated = "2005-08-05" AND subject = "$SUBJECT"});
is( $tix->count, 1);

