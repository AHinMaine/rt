#!/usr/bin/perl -w

use strict;
use RT::Test; use Test::More tests => 7;

use RT;
SKIP: {
skip 'port this test to lorzy', 7;

# {{{ test scrip ordering based on description

my $scrip_queue = RT::Model::Queue->new(current_user => RT->system_user);
my ($queue_id, $msg) = $scrip_queue->create( name => "Scripordering-$$", 
    description => 'Test scrip ordering by description' );
ok($queue_id, "Created scrip-ordering test queue? ".$msg);

my $priority_ten_scrip = RT::Model::Scrip->new(current_user => RT->system_user);
(my $id, $msg) = $priority_ten_scrip->create( 
    description => "10 set priority $$",
    queue => $queue_id, 
    scrip_condition => 'On Create',
    scrip_action => 'User Defined', 
    custom_prepare_code => 'Jifty->log->debug("Setting priority to 10..."); return 1;',
    custom_commit_code => '$self->ticket_obj->set_priority(10);',
    template => 'Blank',
    stage => 'transaction_create',
);
ok($id, "Created priority-10 scrip? ".$msg);

my $priority_five_scrip = RT::Model::Scrip->new(current_user => RT->system_user);
($id, $msg) = $priority_ten_scrip->create( 
    description => "05 set priority $$",
    queue => $queue_id, 
    scrip_condition => 'On Create',
    scrip_action => 'User Defined', 
    custom_prepare_code => 'Jifty->log->debug("Setting priority to 5..."); return 1;',
    custom_commit_code => '$self->ticket_obj->set_priority(5);', 
    template => 'Blank',
    stage => 'transaction_create',
);
ok($id, "Created priority-5 scrip? ".$msg);

my $ticket = RT::Model::Ticket->new(current_user => RT->system_user);
($id, $msg) = $ticket->create( 
    queue => $queue_id, 
    requestor => 'order@example.com',
    subject => "Scrip order test $$",
);
ok($ticket->id, "Created ticket? id=$id");

isnt($ticket->priority , 0, "Ticket shouldn't be priority 0");
isnt($ticket->priority , 5, "Ticket shouldn't be priority 5");
is  ($ticket->priority , 10, "Ticket should be priority 10");

# }}}
}
1;
