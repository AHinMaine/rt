#!/usr/bin/perl
use strict;
use warnings;

use RT::Test;
use Test::More;

plan skip_all => 'GnuPG required.'
    unless eval 'use GnuPG::Interface; 1';
plan skip_all => 'gpg executable is required.'
    unless RT::Test->find_executable('gpg');

plan tests => 176;


use Digest::MD5 qw(md5_hex);

use File::Temp qw(tempdir);
my $homedir = tempdir( CLEANUP => 1 );

RT->config->set(
    'gnupg',
    {
        enable                   => 1,
        outgoing_messages_format => 'RFC',
    }
);

RT->config->set(
    'gnupg_options',
    {
        homedir                 => $homedir,
        passphrase              => 'rt-test',
        'no-permission-warning' => undef,
    }
);

RT->config->set( 'mail_plugins' => ['Auth::MailFrom', 'Auth::GnuPG'] );

RT::Test->import_gnupg_key('rt-recipient@example.com');
RT::Test->import_gnupg_key('rt-test@example.com', 'public');

my ($baseurl, $m) = RT::Test->started_ok;
ok $m->login, 'we did log in';
$m->get_ok( '/Admin/Queues/');
$m->follow_link_ok( {text => 'General'} );
$m->submit_form( form_number => 3,
         fields      => { correspond_address => 'rt-recipient@example.com' } );
$m->content_like(qr/rt-recipient\@example.com.* - never/, 'has key info.');

diag "load Everyone group" if $ENV{'TEST_VERBOSE'};
my $everyone;
{
    $everyone = RT::Model::Group->new(current_user => RT->system_user );
    $everyone->load_system_internal_group('Everyone');
    ok $everyone->id, "loaded 'everyone' group";
}

RT::Test->set_rights(
    principal => $everyone->principal,
    right => ['CreateTicket'],
);


my $eid = 0;
for my $usage (qw/signed encrypted signed&encrypted/) {
    for my $format (qw/MIME inline/) {
        for my $attachment (qw/plain text-attachment binary-attachment/) {
            ++$eid;
            diag "Email $eid: $usage, $attachment email with $format format" if $ENV{TEST_VERBOSE};
            eval { email_ok($eid, $usage, $format, $attachment) };
        }
    }
}

sub email_ok {
    my ($eid, $usage, $format, $attachment) = @_;
    diag "email_ok $eid: $usage, $format, $attachment" if $ENV{'TEST_VERBOSE'};

    my $emaildatadir = RT::Test::get_relocatable_dir(File::Spec->updir(),
        qw(data gnupg emails));
    my ($file) = glob("$emaildatadir/$eid-*");
    my $mail = RT::Test->file_content($file);
    
    my ($status, $id) = RT::Test->send_via_mailgate($mail);
    is ($status >> 8, 0, "$eid: The mail gateway exited normally");
    ok ($id, "$eid: got id of a newly created ticket - $id");

    my $tick = RT::Model::Ticket->new(current_user => RT->system_user );
    $tick->load( $id );
    ok ($tick->id, "$eid: loaded ticket #$id");

    is ($tick->subject,
        "Test Email ID:$eid",
        "$eid: Created the ticket"
    );

    my $txn = $tick->transactions->first;
    my ($msg, @attachments) = @{$txn->attachments->items_array_ref};

    if ($usage =~ /encrypted/) {
        is( $msg->get_header('X-RT-Incoming-Encryption'),
            'Success',
            "$eid: recorded incoming mail that is encrypted" 
        );

        is( $msg->get_header('X-RT-Privacy'),
            'PGP',
            "$eid: recorded incoming mail that is encrypted"
        );

        like( $attachments[0]->content, qr/ID:$eid/,
                "$eid: incoming mail did NOT have original body"
        );
    }
    else {
        is( $msg->get_header('X-RT-Incoming-Encryption'),
            'Not encrypted',
            "$eid: recorded incoming mail that is not encrypted"
        );
        like( $msg->content || $attachments[0]->content, qr/ID:$eid/,
              "$eid: got original content"
        );
    }

    if ($usage =~ /signed/) {
        is( $msg->get_header('X-RT-Incoming-Signature'),
            'RT Test <rt-test@example.com>',
            "$eid: recorded incoming mail that is signed - $usage"
        );
    }
    else {
        is( $msg->get_header('X-RT-Incoming-Signature'),
            undef,
            "$eid: recorded incoming mail that is not signed"
        );
    }

    if ($attachment =~ /attachment/) {
        # signed messages should sign each attachment too
        if ($usage =~ /signed/) {
            my $sig = pop @attachments;
            ok ($sig->id, "$eid: loaded attachment.sig object");
            my $acontent = $sig->content;
        }

        my ($a) = grep $_->filename, @attachments;
        ok ($a && $a->id, "$eid: found attachment with filename");

        my $acontent = $a->content;
        if ($attachment =~ /binary/)
        {
            is(md5_hex($acontent), '1e35f1aa90c98ca2bab85c26ae3e1ba7', "$eid: The binary attachment's md5sum matches");
        }
        else
        {
            like($acontent, qr/zanzibar/, "$eid: The attachment isn't screwed up in the database.");
        }

    }

    return 0;
}

