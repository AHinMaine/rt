#!/usr/bin/perl

use strict;
use warnings;

use RT::Test strict => 1, tests => 41, l10n => 1;


my ($baseurl, $m) = RT::Test->started_ok;
ok $m->login, 'logged in as root';

my $cf_name = 'test select one value';
my $cf_moniker = 'edit-ticket-cfs';

my $cfid;
diag "Create a CF" if $ENV{'TEST_VERBOSE'};
{
    $m->follow_link( text => 'Configuration' );
    $m->title_is(q/RT Administration/, 'admin screen');
    $m->follow_link( text => 'Custom Fields', url_regex =>
            qr!Admin/CustomFields! );
    $m->title_is(q/Select a Custom Field/, 'admin-cf screen');
    $m->follow_link( text => 'Create' );
    $m->submit_form(
        form_name => "modify_custom_field",
        fields => {
            name          => $cf_name,
            type_composite =>   'Select-1',
            lookup_type    => 'RT::Model::Queue-RT::Model::Ticket',
        },
    );
    $m->content_like( qr/created/, 'Created CF sucessfully' );
    $cfid = $m->form_name('modify_custom_field')->value('id');
    ok $cfid, "found id of the CF in the form, it's #$cfid";
}

diag "add 'qwe', 'ASD' and '0' as values to the CF" if $ENV{'TEST_VERBOSE'};
{
    foreach my $value(qw(qwe ASD 0)) {
        $m->submit_form(
            form_name => "modify_custom_field",
            fields => {
                "CustomField-". $cfid ."-value-new-name" => $value,
            },
            button => 'update',
        );
        $m->content_like( qr/created/, 'added a value to the CF' ); # or diag $m->content;
    }
}

my $queue = RT::Test->load_or_create_queue( name => 'General' );
ok $queue && $queue->id, 'loaded or Created queue';

diag "apply the CF to General queue" if $ENV{'TEST_VERBOSE'};
{
    $m->follow_link( text => 'Queues', url_regex => qr!/Admin/Queues! );
    $m->title_is(q/Admin queues/, 'admin-queues screen');
    $m->follow_link( text => 'General', url_regex => qr!/Admin/Queues! );
    $m->title_is(q/Editing Configuration for queue General/, 'admin-queue: general');
    $m->follow_link( text => 'Ticket Custom Fields' );
    $m->title_is(q/Edit Custom Fields for General/, 'admin-queue: general cfid');

    $m->form_name('edit_custom_fields');
    $m->field( "object-". $queue->id ."-CF-$cfid" => 1 );
    $m->submit;

    $m->content_like( qr/created/, 'TCF added to the queue' );
}

my $tid;
diag "create a ticket using API with 'asd'(not 'ASD') as value of the CF"
    if $ENV{'TEST_VERBOSE'};
{
    my $ticket = RT::Model::Ticket->new(current_user => RT->system_user );
    my ($txnid, $msg);
    ($tid, $txnid, $msg) = $ticket->create(
        subject => 'test',
        queue => $queue->id,
        "cf_$cfid" => 'ASD',
    );
    ok $tid, "Created ticket";
    diag $msg if $msg && $ENV{'TEST_VERBOSE'};

    # we use lc as we really don't care about case
    # so if later we'll add canonicalization of value
    # test should work
    is lc $ticket->first_custom_field_value( $cf_name ),
       'asd', 'assigned value of the CF';
}

diag "check that values of the CF are case insensetive(asd vs. ASD)"
    if $ENV{'TEST_VERBOSE'};
{
    ok $m->goto_ticket( $tid ), "opened ticket's page";
    $m->follow_link( url_regex => qr{Ticket/Modify.html} );
    $m->title_like(qr/Modify ticket/i, 'modify ticket');
    $m->content_like(qr/\Q$cf_name/, 'CF on the page');

    my $value = $m->form_name('ticket_modify')->value("J:A:F-$cfid-$cf_moniker");
    is lc $value, 'asd', 'correct value is selected';
    $m->submit;
    $m->content_unlike(qr/\Q$cf_name\E.*?changed/mi, 'field is not changed');

    $value = $m->form_name('ticket_modify')->value("J:A:F-$cfid-$cf_moniker");
    is lc $value, 'asd', 'the same value is still selected';
    my $ticket = RT::Model::Ticket->new(current_user => RT->system_user );
    $ticket->load( $tid );
    ok $ticket->id, 'loaded the ticket';
    is lc $ticket->first_custom_field_value( $cf_name ),
       'asd', 'value is still the same';
}

diag "check that 0 is ok value of the CF"
    if $ENV{'TEST_VERBOSE'};
{
    ok $m->goto_ticket( $tid ), "opened ticket's page";
    $m->follow_link( url_regex => qr{Ticket/Modify.html} );
    $m->title_like(qr/Modify ticket/i, 'modify ticket');
    $m->content_like(qr/\Q$cf_name/, 'CF on the page');

    my $value = $m->form_name('ticket_modify')->value("J:A:F-$cfid-$cf_moniker");
    is lc $value, 'asd', 'correct value is selected';
    $m->select("J:A:F-$cfid-$cf_moniker" => 0 );
    $m->submit;
    $m->content_like(qr/\Q$cf_name\E.*?changed/mi, 'field is changed');
    $m->content_unlike(qr/0 is no longer a value for custom field/mi, 'no bad message in results');

    $value = $m->form_name('ticket_modify')->value("J:A:F-$cfid-$cf_moniker");
    is lc $value, '0', 'new value is selected';

    my $ticket = RT::Model::Ticket->new(current_user => RT->system_user );
    $ticket->load( $tid );
    ok $ticket->id, 'loaded the ticket';
    is lc $ticket->first_custom_field_value( $cf_name ),
       '0', 'API returns correct value';
}

diag "check that we can set empty value when the current is 0"
    if $ENV{'TEST_VERBOSE'};
{
    ok $m->goto_ticket( $tid ), "opened ticket's page";
    $m->follow_link( url_regex => qr{Ticket/Modify.html} );
    $m->title_like(qr/Modify ticket/i, 'modify ticket');
    $m->content_like(qr/\Q$cf_name/, 'CF on the page');

    my $value = $m->form_name('ticket_modify')->value("J:A:F-$cfid-$cf_moniker");
    is lc $value, '0', 'correct value is selected';
    $m->select("J:A:F-$cfid-$cf_moniker" => '' );
    $m->submit;
    $m->content_like(qr/0 is no longer a value for custom field/mi, '0 is no longer a value');

    $value = $m->form_name('ticket_modify')->value("J:A:F-$cfid-$cf_moniker");
    is $value, '', '(no value) is selected';

    my $ticket = RT::Model::Ticket->new(current_user => RT->system_user );
    $ticket->load( $tid );
    ok $ticket->id, 'loaded the ticket';
    is $ticket->first_custom_field_value( $cf_name ),
       undef, 'API returns correct value';
}

