use strict;
use warnings;

use RT::Test tests => 14;

my $ticket = RT::Test->create_ticket(
    Subject => 'test ticket basics',
    Queue   => 1,
);

my ( $url, $m ) = RT::Test->started_ok;
ok( $m->login, 'logged in' );

# Failing test where the time units are not preserved when you
# click 'Add more files' on Display
for (qw/Estimated Worked Left/) {
    $m->goto_create_ticket(1);
    $m->form_name('TicketCreate');
    $m->field("Time${_}" => "1");
    $m->select("Time${_}-TimeUnits" => 'hours');
    $m->click('AddMoreAttach');
    $m->form_name('TicketCreate');
    is($m->value("Time${_}-TimeUnits"), 'hours', 'time units stayed to "hours" after the form was submitted');
}

$m->goto_update_ticket(ticket => $ticket, action => 'Respond');
$m->form_name('TicketUpdate');
$m->select("UpdateTimeWorked-TimeUnits" => 'hours');
$m->click('AddMoreAttach');
$m->form_name('TicketUpdate');
is($m->value("UpdateTimeWorked-TimeUnits"), 'hours', 'time units stayed to "hours" after the form was submitted');

my $cf = RT::Test->load_or_create_custom_field(
    Name       => 'CF1',
    Type       => 'Freeform',
    Pattern    => '.', # mandatory
    Queue      => 'General',
);

# More time unit testing by a failing CF validation
$m->get_ok($url.'/Admin/CustomFields/Objects.html?id='.$cf->id);
$m->form_name('CustomFieldAppliesTo');
$m->tick('AddCustomField-'.$cf->id => '0'); # Make CF global
$m->click('UpdateObjs');
$m->text_contains('Object created', 'CF applied globally');

$m->goto_create_ticket(1);

$m->form_name('TicketCreate');
$m->field('TimeWorked-TimeUnits' => 'hours');
$m->click('SubmitTicket');

$m->form_name('TicketCreate');
is($m->value("TimeWorked-TimeUnits"), 'hours', 'time units stayed to "hours" after the form was submitted');
