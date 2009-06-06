#!/usr/bin/perl -w
# BEGIN BPS TAGGED BLOCK {{{
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2004 Best Practical Solutions, LLC 
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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.gnu.org/copyleft/gpl.html.
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

=head1 NAME

rt-mailgate - Mail interface to RT3.

=cut

use strict;
use warnings;

use RT::Test; use Test::More tests => 159;

my ($baseurl, $ua) = RT::Test->started_ok;

use RT::Model::TicketCollection;

use MIME::Entity;
use Digest::MD5 qw(md5_base64);
use LWP::UserAgent;

# TODO: --extension queue

my $url = $ua->rt_base_url;

sub latest_ticket {
    my $tickets = RT::Model::TicketCollection->new(current_user => RT->system_user );
    $tickets->order_by( { column => 'id', order => 'DESC'} );
    $tickets->limit( column => 'id', operator => '>', value => '0' );
    $tickets->rows_per_page( 1 );
    return $tickets->first;
}

diag "Make sure that when we call the mailgate without URL, it fails" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
To: rt\@@{[RT->config->get('rtname')]}
Subject: This is a test of new ticket creation

Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text, url => undef);
    is ($status >> 8, 1, "The mail gateway exited with a failure");
    ok (!$id, "No ticket id") or diag "by mistake ticket #$id";
}

diag "Make sure that when we call the mailgate with wrong URL, it tempfails" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
To: rt\@@{[RT->config->get('rtname')]}
Subject: This is a test of new ticket creation

Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text, url => 'http://this.test.for.non-connection.is.expected.to.generate.an.error');
    is ($status >> 8, 75, "The mail gateway exited with a failure");
    ok (!$id, "No ticket id");
}

my $everyone_group;
diag "revoke rights tests depend on" if $ENV{'TEST_VERBOSE'};
{
    $everyone_group = RT::Model::Group->new(current_user => RT->system_user );
    $everyone_group->load_system_internal( 'Everyone' );
    ok ($everyone_group->id, "Found group 'everyone'");

    foreach( qw(CreateTicket ReplyToTicket CommentOnTicket) ) {
        $everyone_group->principal->revoke_right(right => $_);
    }
}

diag "Test new ticket creation by root who is privileged and superuser" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
To: rt\@@{[RT->config->get('rtname')]}
Subject: This is a test of new ticket creation

Blah!
Foob!
EOF

    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "Created ticket");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    is ($tick->id, $id, "correct ticket id");
    is ($tick->subject , 'This is a test of new ticket creation', "Created the ticket");
}

diag "Test the 'X-RT-Mail-Extension' field in the header of a ticket" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
To: rt\@@{[RT->config->get('rtname')]}
Subject: This is a test of the X-RT-Mail-Extension field
Blah!
Foob!
EOF
    local $ENV{'EXTENSION'} = "bad value with\nnewlines\n";
    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "Created ticket #$id");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    is ($tick->id, $id, "correct ticket id");
    is ($tick->subject, 'This is a test of the X-RT-Mail-Extension field', "Created the ticket");

    my $transactions = $tick->transactions;
    $transactions->order_by({ column => 'id', order => 'DESC' });
    $transactions->limit( column => 'type', operator => '!=', value => 'email_record');
    my $txn = $transactions->first;
    isa_ok ($txn, 'RT::Model::Transaction');
    is ($txn->type, 'create', "correct type");

    my $attachment = $txn->attachments->first;
    isa_ok ($attachment, 'RT::Model::Attachment');
    # XXX: We eat all newlines in header, that's not what RFC's suggesting
    is (
        $attachment->get_header('X-RT-Mail-Extension'),
        "bad value with newlines",
        'header is in place, without trailing newline char'
    );
}

diag "Make sure that not standard --extension is passed" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
To: rt\@@{[RT->config->get('rtname')]}
Subject: This is a test of new ticket creation

Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text, extension => 'some-extension-arg' );
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "Created ticket #$id");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    is ($tick->id, $id, "correct ticket id");

    my $transactions = $tick->transactions;
    $transactions->order_by({ column => 'id', order => 'DESC' });
    $transactions->limit( column => 'type', operator => '!=', value => 'email_record');
    my $txn = $transactions->first;
    isa_ok ($txn, 'RT::Model::Transaction');
    is ($txn->type, 'create', "correct type");

    my $attachment = $txn->attachments->first;
    isa_ok ($attachment, 'RT::Model::Attachment');
    is (
        $attachment->get_header('X-RT-Mail-Extension'),
        'some-extension-arg',
        'header is in place'
    );
}

diag "Test new ticket creation without --action argument" if $ENV{'TEST_VERBOSE'};
{
    my $rtname = RT->config->get('rtname');

    my $text = <<EOF;
From: root\@localhost
To: rt\@$rtname
Subject: using mailgate without --action arg

Blah!
Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text, extension => 'some-extension-arg' );
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "Created ticket #$id");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    is ($tick->id, $id, "correct ticket id");
    is ($tick->subject, 'using mailgate without --action arg', "using mailgate without --action arg");
}

diag "This is a test of new ticket creation as an unknown user" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist\@@{[RT->config->get('rtname')]}
To: rt\@@{[RT->config->get('rtname')]}
Subject: This is a test of new ticket creation as an unknown user

Blah!
Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok (!$id, "no ticket Created");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    ok ($tick->id, "found ticket ".$tick->id);
    isnt ($tick->subject , 'This is a test of new ticket creation as an unknown user', "failed to create the new ticket from an unprivileged account");

    my $u = RT::Model::User->new(current_user => RT->system_user);
    $u->load("doesnotexist\@@{[RT->config->get('rtname')]}");
    ok( !$u->id, "user does not exist and was not Created by failed ticket submission");
}

diag "grant everybody with CreateTicket right" if $ENV{'TEST_VERBOSE'};
{
    ok( RT::Test->set_rights(
        { principal => $everyone_group->principal,
          right => [qw(CreateTicket)],
        },
    ), "Granted everybody the right to create tickets");
}

my $ticket_id;
diag "now everybody can create tickets. can a random unkown user create tickets?" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist\@@{[RT->config->get('rtname')]}
To: rt\@@{[RT->config->get('rtname')]}
Subject: This is a test of new ticket creation as an unknown user

Blah!
Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "ticket Created");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    ok ($tick->id, "found ticket ".$tick->id);
    is ($tick->id, $id, "correct ticket id");
    is ($tick->subject , 'This is a test of new ticket creation as an unknown user', "failed to create the new ticket from an unprivileged account");

    my $u = RT::Model::User->new(current_user => RT->system_user );
    $u->load( "doesnotexist\@@{[RT->config->get('rtname')]}" );
    ok ($u->id, "user does not exist and was Created by ticket submission");
    $ticket_id = $id;
}

diag "can another random reply to a ticket without being granted privs? answer should be no." if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist-2\@@{[RT->config->get('rtname')]}
To: rt\@@{[RT->config->get('rtname')]}
Subject: [@{[RT->config->get('rtname')]} #$ticket_id] This is a test of a reply as an unknown user

Blah!  (Should not work.)
Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok (!$id, "no way to reply to the ticket");

    my $u = RT::Model::User->new(current_user => RT->system_user);
    $u->load('doesnotexist-2@'.RT->config->get('rtname'));
    ok( !$u->id, " user does not exist and was not Created by ticket correspondence submission");
}

diag "grant everyone 'ReplyToTicket' right" if $ENV{'TEST_VERBOSE'};
{
    ok( RT::Test->set_rights(
        { principal => $everyone_group->principal,
          right => [qw(CreateTicket ReplyToTicket)],
        },
    ), "Granted everybody the right to reply to tickets" );
}

diag "can another random reply to a ticket after being granted privs? answer should be yes" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist-2\@@{[RT->config->get('rtname')]}
To: rt\@@{[RT->config->get('rtname')]}
Subject: [@{[RT->config->get('rtname')]} #$ticket_id] This is a test of a reply as an unknown user

Blah!
Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    is ($id, $ticket_id, "replied to the ticket");

    my $u = RT::Model::User->new(current_user => RT->system_user);
    $u->load('doesnotexist-2@'.RT->config->get('rtname'));
    ok ($u->id, "user exists and was Created by ticket correspondence submission");
}

diag "add a reply to the ticket using '--extension ticket' feature" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist-2\@@{[RT->config->get('rtname')]}
To: rt\@@{[RT->config->get('rtname')]}
Subject: This is a test of a reply as an unknown user

Blah!
Foob!
EOF
    local $ENV{'EXTENSION'} = $ticket_id;
    my ($status, $id) = RT::Test->send_via_mailgate($text, extension => 'ticket');
    is ($status >> 8, 0, "The mail gateway exited normally");
    is ($id, $ticket_id, "replied to the ticket");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    ok ($tick->id, "found ticket ".$tick->id);
    is ($tick->id, $id, "correct ticket id");

    my $transactions = $tick->transactions;
    $transactions->order_by({ column => 'id', order => 'DESC' });
    $transactions->limit( column => 'type', operator => '!=', value => 'email_record');
    my $txn = $transactions->first;
    isa_ok ($txn, 'RT::Model::Transaction');
    is ($txn->type, 'correspond', "correct type");

    my $attachment = $txn->attachments->first;
    isa_ok ($attachment, 'RT::Model::Attachment');
    is ($attachment->get_header('X-RT-Mail-Extension'), $id, 'header is in place');
}

diag "can another random comment on a ticket without being granted privs? answer should be no" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist-3\@@{[RT->config->get('rtname')]}
To: rt\@@{[RT->config->get('rtname')]}
Subject: [@{[RT->config->get('rtname')]} #$ticket_id] This is a test of a comment as an unknown user

Blah!  (Should not work.)
Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text, action => 'comment');
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok (!$id, "no way to comment on the ticket");

    my $u = RT::Model::User->new(current_user => RT->system_user);
    $u->load('doesnotexist-3@'.RT->config->get('rtname'));
    ok( !$u->id, " user does not exist and was not Created by ticket comment submission");
}


diag "grant everyone 'CommentOnTicket' right" if $ENV{'TEST_VERBOSE'};
{
    ok( RT::Test->set_rights(
        { principal => $everyone_group->principal,
          right => [qw(CreateTicket ReplyToTicket CommentOnTicket)],
        },
    ), "Granted everybody the right to comment on tickets");
}

diag "can another random reply to a ticket after being granted privs? answer should be yes" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist-3\@@{[RT->config->get('rtname')]}
To: rt\@@{[RT->config->get('rtname')]}
Subject: [@{[RT->config->get('rtname')]} #$ticket_id] This is a test of a comment as an unknown user

Blah!
Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text, action => 'comment');
    is ($status >> 8, 0, "The mail gateway exited normally");
    is ($id, $ticket_id, "replied to the ticket");

    my $u = RT::Model::User->new(current_user => RT->system_user);
    $u->load('doesnotexist-3@'.RT->config->get('rtname'));
    ok ($u->id, " user exists and was Created by ticket comment submission");
}

diag "add comment to the ticket using '--extension action' feature" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist-3\@@{[RT->config->get('rtname')]}
To: rt\@@{[RT->config->get('rtname')]}
Subject: [@{[RT->config->get('rtname')]} #$ticket_id] This is a test of a comment via '--extension action'

Blah!
Foob!
EOF
    local $ENV{'EXTENSION'} = 'comment';
    my ($status, $id) = RT::Test->send_via_mailgate($text, extension => 'action');
    is ($status >> 8, 0, "The mail gateway exited normally");
    is ($id, $ticket_id, "added comment to the ticket");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    ok ($tick->id, "found ticket ".$tick->id);
    is ($tick->id, $id, "correct ticket id");

    my $transactions = $tick->transactions;
    $transactions->order_by({ column => 'id', order => 'DESC' });
    $transactions->limit(
        column => 'type',
        operator => 'NOT ENDSWITH',
        value => 'email_record',
        entry_aggregator => 'AND',
    );
    my $txn = $transactions->first;
    isa_ok ($txn, 'RT::Model::Transaction');
    is ($txn->type, 'comment', "correct type");

    my $attachment = $txn->attachments->first;
    isa_ok ($attachment, 'RT::Model::Attachment');
    is ($attachment->get_header('X-RT-Mail-Extension'), 'comment', 'header is in place');
}

diag "Testing preservation of binary attachments" if $ENV{'TEST_VERBOSE'};
{
    # Get a binary blob (Best Practical logo) 
    my $LOGO_FILE = Jifty::Util->app_root .'/share/html/NoAuth/images/bplogo.gif';

    # Create a mime entity with an attachment
    my $entity = MIME::Entity->build(
        From    => 'root@localhost',
        To      => 'rt@localhost',
        Subject => 'binary attachment test',
        Data    => ['This is a test of a binary attachment'],
    );

    $entity->attach(
        Path     => $LOGO_FILE,
        Type     => 'image/gif',
        Encoding => 'base64',
    );
    # Create a ticket with a binary attachment
    my ($status, $id) = RT::Test->send_via_mailgate($entity);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "Created ticket");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    ok ($tick->id, "found ticket ".$tick->id);
    is ($tick->id, $id, "correct ticket id");
    is ($tick->subject , 'binary attachment test', "Created the ticket - ".$tick->id);

    my $file = `cat $LOGO_FILE`;
    ok ($file, "Read in the logo image");
    diag "for the raw file the md5 hex is ". Digest::MD5::md5_hex($file) if $ENV{'TEST_VERBOSE'};

    # Verify that the binary attachment is valid in the database
    my $attachments = RT::Model::AttachmentCollection->new(current_user => RT->system_user);
    $attachments->limit(column => 'content_type', value => 'image/gif');
    my $txn_alias = $attachments->join(
        alias1 => 'main',
        column1 => 'transaction_id',
        table2 => 'Transactions',
        column2 => 'id',
    );
    $attachments->limit( alias => $txn_alias, column => 'object_type', value => 'RT::Model::Ticket' );
    $attachments->limit( alias => $txn_alias, column => 'object_id', value => $id );
    is ($attachments->count, 1, 'Found only one gif attached to the ticket');
    my $attachment = $attachments->first;
    ok ($attachment->id, 'loaded attachment object');
    my $acontent = $attachment->content;

    diag "coming from the database, md5 hex is ".Digest::MD5::md5_hex($acontent) if $ENV{'TEST_VERBOSE'};
    is ($acontent, $file, 'The attachment isn\'t screwed up in the database.');

    # Grab the binary attachment via the web ui
    my $full_url = "$url/Ticket/Attachment/". $attachment->transaction_id
        ."/". $attachment->id. "/bplogo.gif";
        $ua->login();
    my $r = $ua->get( $full_url );

    # Verify that the downloaded attachment is the same as what we uploaded.
    is ($file, $r->content, 'The attachment isn\'t screwed up in download');
}

diag "Simple I18N testing" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
To: rtemail\@@{[RT->config->get('rtname')]}
Subject: This is a test of I18N ticket creation
Content-Type: text/plain; charset="utf-8"

2 accented lines
\303\242\303\252\303\256\303\264\303\273
\303\241\303\251\303\255\303\263\303\272
bye
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "Created ticket");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    ok ($tick->id, "found ticket ". $tick->id);
    is ($tick->id, $id, "correct ticket");
    is ($tick->subject , 'This is a test of I18N ticket creation', "Created the ticket - ". $tick->subject);

    my $unistring = "\303\241\303\251\303\255\303\263\303\272";
    Encode::_utf8_on($unistring);
    is (
        $tick->transactions->first->content,
        $tick->transactions->first->attachments->first->content,
        "content is ". $tick->transactions->first->attachments->first->content
    );
    ok (
        $tick->transactions->first->content =~ /$unistring/i,
        $tick->id." appears to be unicode ". $tick->transactions->first->attachments->first->id
    );
}

diag "supposedly I18N fails on the second message sent in." if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
To: rtemail\@@{[RT->config->get('rtname')]}
Subject: This is a test of I18N ticket creation
Content-Type: text/plain; charset="utf-8"

2 accented lines
\303\242\303\252\303\256\303\264\303\273
\303\241\303\251\303\255\303\263\303\272
bye
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "Created ticket");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    ok ($tick->id, "found ticket ". $tick->id);
    is ($tick->id, $id, "correct ticket");
    is ($tick->subject , 'This is a test of I18N ticket creation', "Created the ticket");

    my $unistring = "\303\241\303\251\303\255\303\263\303\272";
    Encode::_utf8_on($unistring);

    ok (
        $tick->transactions->first->content =~ $unistring,
        "It appears to be unicode - ". $tick->transactions->first->content
    );
}

diag "check that mailgate doesn't suffer from empty Reply-To:" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
Reply-To: 
To: rtemail\@@{[RT->config->get('rtname')]}
Subject: test
Content-Type: text/plain; charset="utf-8"
 
test
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "created ticket");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    ok ($tick->id, "found ticket ". $tick->id);
    is ($tick->id, $id, "correct ticket");

    like $tick->role_group("requestor")->member_emails_as_string, qr/root\@localhost/, 'correct requestor';
}


my ($val,$msg) = $everyone_group->principal->revoke_right(right => 'CreateTicket');
ok ($val, $msg);

SKIP: {
skip "Advanced mailgate actions require an unsafe configuration", 47
    unless RT->config->get('unsafe_email_commands');

# create new queue to be shure we don't mess with rights
use RT::Model::Queue;
my $queue = RT::Model::Queue->new(current_user => RT->system_user);
my ($qid) = $queue->create( name => 'ext-mailgate');
ok( $qid, 'queue Created for ext-mailgate tests' );

# {{{ Check take and resolve actions

# create ticket that is owned by nobody
use RT::Model::Ticket;
my $tick = RT::Model::Ticket->new(current_user => RT->system_user);
my ($id) = $tick->create( queue => 'ext-mailgate', subject => 'test');
ok( $id, 'new ticket Created' );
is( $tick->owner, RT->nobody->id, 'owner of the new ticket is nobody' );

my $mail = RT::Test->open_mailgate_ok($baseurl);
print $mail <<EOF; 
From: root\@localhost
Subject: [@{[RT->config->get('rtname')]} \#$id] test

EOF
RT::Test->close_mailgate_ok($mail);

$tick = RT::Model::Ticket->new(current_user => RT->system_user);
$tick->load( $id );
is( $tick->id, $id, 'load correct ticket');
is( $tick->owner_obj->email, 'root@localhost', 'successfuly take ticket via email');

# check that there is no text transactions writen
is( $tick->transactions->count, 2, 'no superfluous transactions');

my $status;
($status, $msg) = $tick->set_owner( RT->nobody->id, 'Force' );
ok( $status, 'successfuly changed owner: '. ($msg||'') );
is( $tick->owner, RT->nobody->id, 'set owner back to nobody');


$mail = RT::Test->open_mailgate_ok($baseurl);
print $mail <<EOF;
From: root\@localhost
Subject: [@{[RT->config->get('rtname')]} \#$id] correspondence

test
EOF
RT::Test->close_mailgate_ok($mail);

Jifty::DBI::Record::Cachable->flush_cache;

$tick = RT::Model::Ticket->new(current_user => RT->system_user);
$tick->load( $id );
is( $tick->id, $id, "load correct ticket #$id");
is( $tick->owner_obj->email, 'root@localhost', 'successfuly take ticket via email');
my $txns = $tick->transactions;
$txns->limit( column => 'type', value => 'correspond');
$txns->order_by( column => 'id', order => 'DESC' );
# +1 because of auto open
is( $tick->transactions->count, 6, 'no superfluous transactions');
my $rtname = RT->config->get('rtname');
is( $txns->first->subject, "[$rtname \#$id] correspondence", 'successfuly add correspond within take via email' );

$mail = RT::Test->open_mailgate_ok($baseurl);
print $mail <<EOF;
From: root\@localhost
Subject: [@{[RT->config->get('rtname')]} \#$id] test

EOF
RT::Test->close_mailgate_ok($mail);

Jifty::DBI::Record::Cachable->flush_cache;

$tick = RT::Model::Ticket->new(current_user => RT->system_user);
$tick->load( $id );
is( $tick->id, $id, 'load correct ticket');
is( $tick->status, 'resolved', 'successfuly resolved ticket via email');
is( $tick->transactions->count, 7, 'no superfluous transactions');

use RT::Model::User;
my $user = RT::Model::User->new(current_user => RT->system_user );
my ($uid) = $user->create( name => 'ext-mailgate',
			   email => 'ext-mailgate@localhost',
			   privileged => 1,
			   password => 'qwe123',
			 );
ok( $uid, 'user Created for ext-mailgate tests' );
ok( !$user->has_right( right => 'OwnTicket', object => $queue ), "User can't own ticket" );

$tick = RT::Model::Ticket->new(current_user => RT->system_user);
($id) = $tick->create( queue => $qid, subject => 'test' );
ok( $id, 'create new ticket' );

my $rtname = RT->config->get('rtname');

$mail = RT::Test->open_mailgate_ok($baseurl);
print $mail <<EOF;
From: ext-mailgate\@localhost
Subject: [$rtname \#$id] test

EOF
RT::Test->close_mailgate_ok($mail);
Jifty::DBI::Record::Cachable->flush_cache;

cmp_ok( $tick->owner, '!=', $user->id, "we didn't change owner" );

($status, $msg) = $user->principal->grant_right( object => $queue, right => 'ReplyToTicket' );
ok( $status, "successfuly granted right: $msg" );
my $ace_id = $status;
ok( $user->has_right( right => 'ReplyToTicket', object => $tick ), "User can reply to ticket" );

$mail = RT::Test->open_mailgate_ok($baseurl);
print $mail <<EOF;
From: ext-mailgate\@localhost
Subject: [$rtname \#$id] test

correspond-take
EOF
RT::Test->close_mailgate_ok($mail);
Jifty::DBI::Record::Cachable->flush_cache;

cmp_ok( $tick->owner, '!=', $user->id, "we didn't change owner" );
is( $tick->transactions->count, 3, "one transactions added" );

$mail = RT::Test->open_mailgate_ok($baseurl);
print $mail <<EOF;
From: ext-mailgate\@localhost
Subject: [$rtname \#$id] test

correspond-take
EOF
RT::Test->close_mailgate_ok($mail);
Jifty::DBI::Record::Cachable->flush_cache;

cmp_ok( $tick->owner, '!=', $user->id, "we didn't change owner" );
is( $tick->transactions->count, 3, "no transactions added, user can't take ticket first" );

# revoke ReplyToTicket right
use RT::Model::ACE;
my $ace = RT::Model::ACE->new(current_user => RT->system_user);
$ace->load( $ace_id );
$ace->delete;
my $acl = RT::Model::ACECollection->new(current_user => RT->system_user);
$acl->limit( column => 'right_name', value => 'ReplyToTicket' );
$acl->limit_to_object( RT->system );
while( my $ace = $acl->next ) {
	$ace->delete;
}

ok( !$user->has_right( right => 'ReplyToTicket', object => $tick ), "User can't reply to ticket any more" );


my $group = RT::Model::Group->new(current_user => RT->system_user );
ok( $group->create_role( object => $queue, type=> 'owner' ), "load queue owners role group" );
$ace = RT::Model::ACE->new(current_user => RT->system_user );
($ace_id, $msg) = $group->principal->grant_right( right => 'ReplyToTicket', object => $queue );
ok( $ace_id, "Granted queue owners role group with ReplyToTicket right" );

($status, $msg) = $user->principal->grant_right( object => $queue, right => 'OwnTicket' );
ok( $status, "successfuly granted right: $msg" );
($status, $msg) = $user->principal->grant_right( object => $queue, right => 'TakeTicket' );
ok( $status, "successfuly granted right: $msg" );

$mail = RT::Test->open_mailgate_ok($baseurl);
print $mail <<EOF;
From: ext-mailgate\@localhost
Subject: [$rtname \#$id] test

take-correspond with reply Right granted to owner role
EOF
RT::Test->close_mailgate_ok($mail);
Jifty::DBI::Record::Cachable->flush_cache;

$tick->load( $id );
is( $tick->owner, $user->id, "we changed owner" );
ok( $user->has_right( right => 'ReplyToTicket', object => $tick ), "owner can reply to ticket" );
is( $tick->transactions->count, 5, "transactions added" );
$txns = $tick->transactions;
while (my $t = $txns->next) {
    diag( $t->id, $t->description."\n");
}

# }}}
};


1;

