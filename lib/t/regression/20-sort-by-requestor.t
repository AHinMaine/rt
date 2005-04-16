#!/usr/bin/perl -w
use strict; use warnings;

use Test::More qw/no_plan/;
use_ok('RT');
RT::LoadConfig();
RT::Init();
use RT::Ticket;

my $q = RT::Queue->new($RT::SystemUser);
my $queue = 'SearchTests-'.rand(200);
$q->Create(Name => $queue);

my @requestors = ( ('bravo@example.com') x 5, ('alpha@example.com') x 5,
                   ('delta@example.com') x 5, ('charlie@example.com') x 5);
my @subjects = ("first test", "second test", "third test", "fourth test") x 5;
while (@requestors) {
    my $t = RT::Ticket->new($RT::SystemUser);
    my ( $id, undef $msg ) = $t->Create(
        Queue      => $q->id,
        Subject    => shift @subjects,
        Requestor => [ shift @requestors ]
    );
    ok( $id, $msg );
}

{
    my $tix = RT::Tickets->new($RT::SystemUser);
    $tix->FromSQL("Queue = '$queue'");
    is($tix->Count, 20, "found twenty tickets");
}

{
    my $tix = RT::Tickets->new($RT::SystemUser);
    $tix->FromSQL("Queue = '$queue' AND requestor = 'alpha\@example.com'");
    $tix->OrderByCols({ FIELD => "Subject" });
    my @subjects;
    while (my $t = $tix->Next) { push @subjects, $t->Subject; }
    is(@subjects, 5, "found five tickets");
    is_deeply( \@subjects, [ sort @subjects ], "Subjects are sorted");
}

{
    my $tix = RT::Tickets->new($RT::SystemUser);
    $tix->FromSQL("Queue = '$queue' AND subject = 'first test' AND Requestor.EmailAddress LIKE 'example.com'");
    $tix->OrderByCols({ FIELD => "Requestor.EmailAddress" });
    my @mails;
    while (my $t = $tix->Next) { push @mails, $t->RequestorAddresses; }
    is(@mails, 5, "found five tickets");
    is_deeply( \@mails, [ sort @mails ], "Addresses are sorted");
}

{
    my $tix = RT::Tickets->new($RT::SystemUser);
    $tix->FromSQL("Queue = '$queue' AND subject = 'first test'");
    $tix->OrderByCols({ FIELD => "Requestor.EmailAddress" });
    my @mails;
    while (my $t = $tix->Next) { push @mails, $t->RequestorAddresses; }
    is(@mails, 5, "found five tickets");
    is_deeply( \@mails, [ sort @mails ], "Addresses are sorted");
}

# vim:ft=perl:
