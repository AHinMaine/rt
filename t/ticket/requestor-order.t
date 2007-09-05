#!/usr/bin/perl -w
use strict; use warnings;

use Test::More;
plan tests => 58;
use_ok('RT');
use RT::Test;

use RT::Model::Ticket;

my $q = RT::Model::Queue->new($RT::SystemUser);
my $queue = 'SearchTests-'.rand(200);
$q->create(Name => $queue);

my @requestors = ( ('bravo@example.com') x 6, ('alpha@example.com') x 6,
                   ('delta@example.com') x 6, ('charlie@example.com') x 6,
                   (undef) x 6);
my @subjects = ("first test", "second test", "third test", "fourth test", "fifth test") x 6;
while (@requestors) {
    my $t = RT::Model::Ticket->new($RT::SystemUser);
    my ( $id, undef $msg ) = $t->create(
        Queue      => $q->id,
        Subject    => shift @subjects,
        Requestor => [ shift @requestors ]
    );
    ok( $id, $msg );
}

{
    my $tix = RT::Model::Tickets->new($RT::SystemUser);
    $tix->from_sql("Queue = '$queue'");
    is($tix->count, 30, "found thirty tickets");
}

{
    my $tix = RT::Model::Tickets->new($RT::SystemUser);
    $tix->from_sql("Queue = '$queue' AND requestor = 'alpha\@example.com'");
    $tix->order_by({ column => "Subject" });
    my @subjects;
    while (my $t = $tix->next) { push @subjects, $t->Subject; }
    is(@subjects, 6, "found six tickets");
    is_deeply( \@subjects, [ sort @subjects ], "Subjects are sorted");
}

sub check_emails_order
{
    my ($tix,$count,$order) = (@_);
    my @mails;
    while (my $t = $tix->next) { push @mails, $t->RequestorAddresses; }
    is(@mails, $count, "found $count tickets for ". $tix->Query);
    my @required_order;
    if( $order =~ /asc/i ) {
        @required_order = sort { $a? ($b? ($a cmp $b) : -1) : 1} @mails;
    } else {
        @required_order = sort { $a? ($b? ($b cmp $a) : -1) : 1} @mails;
    }
    foreach( reverse splice @mails ) {
        if( $_ ) { unshift @mails, $_ }
        else { push @mails, $_ }
    }
    is_deeply( \@mails, \@required_order, "Addresses are sorted");
}

{
    my $tix = RT::Model::Tickets->new($RT::SystemUser);
    $tix->from_sql("Queue = '$queue' AND subject = 'first test' AND Requestor.EmailAddress LIKE 'example.com'");
    $tix->order_by({ column => "Requestor.EmailAddress" });
    check_emails_order($tix, 5, 'ASC');
    $tix->order_by({ column => "Requestor.EmailAddress", order => 'DESC' });
    check_emails_order($tix, 5, 'DESC');
}

{
    my $tix = RT::Model::Tickets->new($RT::SystemUser);
    $tix->from_sql("Queue = '$queue' AND Subject = 'first test'");
    $tix->order_by({ column => "Requestor.EmailAddress" });
    check_emails_order($tix, 6, 'ASC');
    $tix->order_by({ column => "Requestor.EmailAddress", order => 'DESC' });
    check_emails_order($tix, 6, 'DESC');
}


{
    my $tix = RT::Model::Tickets->new($RT::SystemUser);
    $tix->from_sql("Queue = '$queue' AND Subject = 'first test'");
    $tix->order_by({ column => "Requestor.EmailAddress" });
    check_emails_order($tix, 6, 'ASC');
    $tix->order_by({ column => "Requestor.EmailAddress", order => 'DESC' });
    check_emails_order($tix, 6, 'DESC');
}

{
    # create ticket with group as member of the requestors group
    my $t = RT::Model::Ticket->new($RT::SystemUser);
    my ( $id, $msg ) = $t->create(
        Queue      => $q->id,
        Subject    => "first test",
        Requestor  => 'badaboom@example.com',
    );
    ok( $id, "ticket Created" ) or diag( "error: $msg" );

    my $g = RT::Model::Group->new($RT::SystemUser);

    my ($gid);
    ($gid, $msg) = $g->create_userDefinedGroup(Name => '20-sort-by-requestor.t-'.rand(200));
    ok($gid, "Created group") or diag("error: $msg");

    ($id, $msg) = $t->Requestors->AddMember( $gid );
    ok($id, "added group to requestors group") or diag("error: $msg");
}

    my $tix = RT::Model::Tickets->new($RT::SystemUser);    
    $tix->from_sql("Queue = '$queue' AND Subject = 'first test'");
TODO: {
    local $TODO = "if group has non users members we get wrong order";
    $tix->order_by({ column => "Requestor.EmailAddress" });
    check_emails_order($tix, 7, 'ASC');
}
    $tix->order_by({ column => "Requestor.EmailAddress", order => 'DESC' });
    check_emails_order($tix, 7, 'DESC');

{
    my $tix = RT::Model::Tickets->new($RT::SystemUser);
    $tix->from_sql("Queue = '$queue'");
    $tix->order_by({ column => "Requestor.EmailAddress" });
    $tix->rows_per_page(30);
    my @mails;
    while (my $t = $tix->next) { push @mails, $t->RequestorAddresses; }
    is(@mails, 30, "found thirty tickets");
    is_deeply( [grep {$_} @mails], [ sort grep {$_} @mails ], "Paging works (exclude nulls, which are db-dependant)");
}

{
    my $tix = RT::Model::Tickets->new($RT::SystemUser);
    $tix->from_sql("Queue = '$queue'");
    $tix->order_by({ column => "Requestor.EmailAddress" });
    $tix->rows_per_page(30);
    my @mails;
    while (my $t = $tix->next) { push @mails, $t->RequestorAddresses; }
    is(@mails, 30, "found thirty tickets");
    is_deeply( [grep {$_} @mails], [ sort grep {$_} @mails ], "Paging works (exclude nulls, which are db-dependant)");
}
RT::Test->mailsent_ok(25);

# vim:ft=perl:
