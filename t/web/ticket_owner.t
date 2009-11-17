#!/usr/bin/perl

use strict;
use warnings;

use RT::Test strict => 0, tests => 93, l10n => 1;


my $queue = RT::Test->load_or_create_queue( name => 'Regression' );
ok $queue && $queue->id, 'loaded or created queue';

my $user_a = RT::Test->load_or_create_user(
    name => 'user_a', password => 'password',
);
ok $user_a && $user_a->id, 'loaded or created user';

my $user_b = RT::Test->load_or_create_user(
    name => 'user_b', password => 'password',
);
ok $user_b && $user_b->id, 'loaded or created user';

RT::Test->started_ok;

ok( RT::Test->set_rights(
    { principal => $user_a, right => [qw(SeeQueue ShowTicket CreateTicket ReplyToTicket)] },
    { principal => $user_b, right => [qw(SeeQueue ShowTicket OwnTicket)] },
), 'set rights');

my $agent_a = RT::Test::Web->new;
ok $agent_a->login('user_a', 'password'), 'logged in as user A';

diag "current user has no right to own, nobody selected as owner on create" if $ENV{TEST_VERBOSE};
{
    $agent_a->get_ok('/', 'open home page');
    $agent_a->form_name('create_ticket_in_queue');
    $agent_a->select( 'queue', $queue->id );
    $agent_a->submit;

    $agent_a->content_like(qr/Create a new ticket/i, 'opened create ticket page');
    my $form = $agent_a->form_name('ticket_create');
    my $moniker = $agent_a->moniker_for('RT::Action::CreateTicket');
    my $owner_field = $agent_a->action_field_input($moniker, 'owner');

    is $owner_field->value, RT->nobody->id, 'correct owner selected';
    ok !grep($_ == $user_a->id, $owner_field->possible_values),
        'user A can not own tickets';
    $agent_a->submit;
    $agent_a->content_like(qr/Created ticket #\d+ in queue/i, 'created ticket');
    my ($id) = ($agent_a->content =~ /Created ticket #(\d+) in queue/);
    ok $id, 'found id of the ticket';
    my $ticket = RT::Model::Ticket->new(current_user => RT->system_user );
    $ticket->load( $id );
    ok $ticket->id, 'loaded the ticket';
    is $ticket->owner->id, RT->nobody->id, 'correct owner';
}

diag "user can chose owner of a new ticket" if $ENV{TEST_VERBOSE};
{
    $agent_a->get_ok('/', 'open home page');
    $agent_a->form_name('create_ticket_in_queue');
    $agent_a->select( 'queue', $queue->id );
    $agent_a->submit;

    $agent_a->content_like(qr/Create a new ticket/i, 'opened create ticket page');
    my $moniker = $agent_a->moniker_for('RT::Action::CreateTicket');
    my $owner_field = $agent_a->action_field_input($moniker, 'owner');

    is $owner_field->value, RT->nobody->id, 'correct owner selected';

    ok grep($_ == $user_b->id, $owner_field->possible_values),
        'user B is listed as potential owner';
    $owner_field->value($user_b->id);
    $agent_a->submit;

    $agent_a->content_like(qr/Created ticket #\d+ in queue/i, 'created ticket');
    my ($id) = ($agent_a->content =~ /Created ticket #(\d+) in queue/);
    ok $id, 'found id of the ticket';

    my $ticket = RT::Model::Ticket->new(current_user => RT->system_user );
    $ticket->load( $id );
    ok $ticket->id, 'loaded the ticket';
    is $ticket->owner->id, $user_b->id, 'correct owner';
}

my $agent_b = RT::Test::Web->new;
ok $agent_b->login('user_b', 'password'), 'logged in as user B';

diag "user A can not change owner after create" if $ENV{TEST_VERBOSE};
{
    my $ticket = RT::Model::Ticket->new( current_user => RT::CurrentUser->new(id => $user_a->id ));
    my ($id, $txn, $msg) = $ticket->create(
        queue => $queue->id,
        owner => $user_b->id,
        subject => 'test',
    );
    ok $id, 'created a ticket #'. $id or diag "error: $msg";
    is $ticket->owner->id, $user_b->id, 'correct owner';

    # try the following group of tests twice with different agents(logins)
    my $test_cb = sub  {
        my $agent = shift;
        $agent->goto_ticket( $id );
        diag("Going to ticket $id") if $ENV{TEST_VERBOSE};
        $agent->follow_link_ok(text => 'Basics');
        my $form = $agent->form_number(3);
        is $agent->action_field_value(
            $agent->moniker_for('RT::Action::UpdateTicket'), 'owner'
          ),
          $user_b->id, 'correct owner selected';
        $agent->fill_in_action_ok(
            $agent->moniker_for("RT::Action::UpdateTicket"),
            owner => RT->nobody->id );
        $agent->submit;

        $agent->content_like(
            qr/Permission denied/i,
            'no way to change owner after create if you have no rights'
        );

        my $ticket = RT::Model::Ticket->new(current_user => RT->system_user );
        $ticket->load( $id );
        ok $ticket->id, 'loaded the ticket';
        is $ticket->owner->id, $user_b->id, 'correct owner';
    };

    $test_cb->($agent_a);
    diag "even owner(user B) can not change owner" if $ENV{TEST_VERBOSE};
    $test_cb->($agent_b);
}

diag "on reply correct owner is selected" if $ENV{TEST_VERBOSE};
{
    my $ticket = RT::Model::Ticket->new(current_user => RT::CurrentUser->new(id => $user_a->id ));
    my ($id, $txn, $msg) = $ticket->create(
        queue => $queue->id,
        owner => $user_b->id,
        subject => 'test',
    );
    ok $id, 'created a ticket #'. $id or diag "error: $msg";
    is $ticket->owner->id, $user_b->id, 'correct owner';

    $agent_a->goto_ticket( $id );
    $agent_a->follow_link_ok(text => 'Reply');

    my $form = $agent_a->form_number(3);
    is $form->value('owner'), '', 'empty value selected';
    $agent_a->submit;

    $ticket = RT::Model::Ticket->new(current_user => RT->system_user );
    $ticket->load( $id );
    ok $ticket->id, 'loaded the ticket';
    is $ticket->owner->id, $user_b->id, 'correct owner';
}

ok( RT::Test->set_rights(
    { principal => $user_a, right => [qw(SeeQueue ShowTicket CreateTicket OwnTicket)] },
    { principal => $user_b, right => [qw(SeeQueue ShowTicket OwnTicket)] },
), 'set rights');

diag "Couldn't take without coresponding right" if $ENV{TEST_VERBOSE};
{
    my $ticket = RT::Model::Ticket->new(current_user => RT::CurrentUser->new(id => $user_a->id ));
    my ($id, $txn, $msg) = $ticket->create(
        queue => $queue->id,
        subject => 'test',
    );
    ok $id, 'created a ticket #'. $id or diag "error: $msg";
    is $ticket->owner->id, RT->nobody->id, 'correct owner';

    $agent_a->goto_ticket( $id );
    ok !($agent_a->find_all_links( text => 'Take' ))[0],
        'no Take link';
    ok !($agent_a->find_all_links( text => 'Steal' ))[0],
        'no Steal link as well';
}

diag "Couldn't steal without coresponding right" if $ENV{TEST_VERBOSE};
{
    my $ticket = RT::Model::Ticket->new(current_user => RT::CurrentUser->new(id => $user_a->id ));
    my ($id, $txn, $msg) = $ticket->create(
        queue => $queue->id,
        owner => $user_b->id,
        subject => 'test',
    );
    ok $id, 'created a ticket #'. $id or diag "error: $msg";
    is $ticket->owner->id, $user_b->id, 'correct owner';

    $agent_a->goto_ticket( $id );
    ok !($agent_a->find_all_links( text => 'Steal' ))[0],
        'no Steal link';
    ok !($agent_a->find_all_links( text => 'Take' ))[0],
        'no Take link as well';
}

ok( RT::Test->set_rights(
    { principal => $user_a, right => [qw(SeeQueue ShowTicket CreateTicket TakeTicket)] },
), 'set rights');

diag "TakeTicket require OwnTicket to work" if $ENV{TEST_VERBOSE};
{
    my $ticket = RT::Model::Ticket->new(current_user => RT::CurrentUser->new(id => $user_a->id ));
    my ($id, $txn, $msg) = $ticket->create(
        queue => $queue->id,
        subject => 'test',
    );
    ok $id, 'created a ticket #'. $id or diag "error: $msg";
    is $ticket->owner->id, RT->nobody->id, 'correct owner';

    $agent_a->goto_ticket( $id );
    ok !($agent_a->find_all_links( text => 'Take' ))[0],
        'no Take link';
    ok !($agent_a->find_all_links( text => 'Steal' ))[0],
        'no Steal link as well';
}

ok( RT::Test->set_rights(
    { principal => $user_a, right => [qw(SeeQueue ShowTicket CreateTicket OwnTicket TakeTicket)] },
    { principal => $user_b, right => [qw(SeeQueue ShowTicket OwnTicket)] },
), 'set rights');

diag "TakeTicket+OwnTicket work" if $ENV{TEST_VERBOSE};
{
    my $ticket = RT::Model::Ticket->new(current_user => RT::CurrentUser->new(id => $user_a->id ));
    my ($id, $txn, $msg) = $ticket->create(
        queue => $queue->id,
        subject => 'test',
    );
    ok $id, 'created a ticket #'. $id or diag "error: $msg";
    is $ticket->owner->id, RT->nobody->id, 'correct owner';

    $agent_a->goto_ticket( $id );
    ok !($agent_a->find_all_links( text => 'Steal' ))[0],
        'no Steal link';
    $agent_a->follow_link_ok(text => 'Take');

    $ticket = RT::Model::Ticket->new(current_user => RT->system_user );
    $ticket->load( $id );
    ok $ticket->id, 'loaded the ticket';
    is $ticket->owner->id, $user_a->id, 'correct owner';
}

diag "TakeTicket+OwnTicket don't work when owner is not nobody" if $ENV{TEST_VERBOSE};
{
    my $ticket = RT::Model::Ticket->new( current_user => RT::CurrentUser->new(id => $user_a->id ));
    my ($id, $txn, $msg) = $ticket->create(
        queue => $queue->id,
        owner => $user_b->id,
        subject => 'test',
    );
    ok $id, 'created a ticket #'. $id or diag "error: $msg";
    is $ticket->owner->id, $user_b->id, 'correct owner';

    $agent_a->goto_ticket( $id );
    ok !($agent_a->find_all_links( text => 'Take' ))[0],
        'no Take link';
    ok !($agent_a->find_all_links( text => 'Steal' ))[0],
        'no Steal link too';
}

ok( RT::Test->set_rights(
    { principal => $user_a, right => [qw(SeeQueue ShowTicket CreateTicket StealTicket)] },
    { principal => $user_b, right => [qw(SeeQueue ShowTicket OwnTicket)] },
), 'set rights');

diag "StealTicket require OwnTicket to work" if $ENV{TEST_VERBOSE};
{
    my $ticket = RT::Model::Ticket->new(current_user => RT::CurrentUser->new(id => $user_a->id ));
    my ($id, $txn, $msg) = $ticket->create(
        queue => $queue->id,
        owner => $user_b->id,
        subject => 'test',
    );
    ok $id, 'created a ticket #'. $id or diag "error: $msg";
    is $ticket->owner->id, $user_b->id, 'correct owner';

    $agent_a->goto_ticket( $id );
    ok !($agent_a->find_all_links( text => 'Steal' ))[0],
        'no Steal link';
    ok !($agent_a->find_all_links( text => 'Take' ))[0],
        'no Take link too';
}

ok( RT::Test->set_rights(
    { principal => $user_a, right => [qw(SeeQueue ShowTicket CreateTicket OwnTicket StealTicket)] },
    { principal => $user_b, right => [qw(SeeQueue ShowTicket OwnTicket)] },
), 'set rights');

diag "StealTicket+OwnTicket work" if $ENV{TEST_VERBOSE};
{
    my $ticket = RT::Model::Ticket->new(current_user => RT::CurrentUser->new(id => $user_a->id ));
    my ($id, $txn, $msg) = $ticket->create(
        queue => $queue->id,
        owner => $user_b->id,
        subject => 'test',
    );
    ok $id, 'created a ticket #'. $id or diag "error: $msg";
    is $ticket->owner->id, $user_b->id, 'correct owner';

    $agent_a->goto_ticket( $id );
    ok !($agent_a->find_all_links( text => 'Take' ))[0],
        'but no Take link';
    $agent_a->follow_link_ok(text => 'Steal');

    $ticket = RT::Model::Ticket->new(current_user => RT->system_user );
    $ticket->load( $id );
    ok $ticket->id, 'loaded the ticket';
    is $ticket->owner->id, $user_a->id, 'correct owner';
}

diag "StealTicket+OwnTicket don't work when owner is nobody" if $ENV{TEST_VERBOSE};
{
    my $ticket = RT::Model::Ticket->new(current_user => RT::CurrentUser->new(id => $user_a->id ));
    my ($id, $txn, $msg) = $ticket->create(
        queue => $queue->id,
        subject => 'test',
    );
    ok $id, 'created a ticket #'. $id or diag "error: $msg";
    is $ticket->owner->id, RT->nobody->id, 'correct owner';

    $agent_a->goto_ticket( $id );
    ok !($agent_a->find_all_links( text => 'Steal' ))[0],
        'no Steal link';
    ok !($agent_a->find_all_links( text => 'Take' ))[0],
        'no Take link as well (no right)';
}

ok( RT::Test->set_rights(
    { principal => $user_a, right => [qw(SeeQueue ShowTicket CreateTicket OwnTicket TakeTicket StealTicket)] },
    { principal => $user_b, right => [qw(SeeQueue ShowTicket OwnTicket)] },
), 'set rights');

diag "no Steal link when owner nobody" if $ENV{TEST_VERBOSE};
{
    my $ticket = RT::Model::Ticket->new(current_user => RT::CurrentUser->new(id => $user_a->id ));
    my ($id, $txn, $msg) = $ticket->create(
        queue => $queue->id,
        subject => 'test',
    );
    ok $id, 'created a ticket #'. $id or diag "error: $msg";
    is $ticket->owner->id, RT->nobody->id, 'correct owner';

    $agent_a->goto_ticket( $id );
    ok !($agent_a->find_all_links( text => 'Steal' ))[0],
        'no Steal link';
    ok( ($agent_a->find_all_links( text => 'Take' ))[0],
        'but have Take link');
}

diag "no Take link when owner is not nobody" if $ENV{TEST_VERBOSE};
{
    my $ticket = RT::Model::Ticket->new(current_user => RT::CurrentUser->new(id => $user_a->id ));
    my ($id, $txn, $msg) = $ticket->create(
        queue => $queue->id,
        owner => $user_b->id,
        subject => 'test',
    );
    ok $id, 'created a ticket #'. $id or diag "error: $msg";
    is $ticket->owner->id, $user_b->id, 'correct owner';

    $agent_a->goto_ticket( $id );
    ok !($agent_a->find_all_links( text => 'Take' ))[0],
        'no Take link';
    ok( ($agent_a->find_all_links( text => 'Steal' ))[0],
        'but have Steal link');
}

