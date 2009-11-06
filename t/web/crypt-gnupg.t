#!/usr/bin/perl -w
use strict;

use Test::More;
use RT::Test strict => 1;

plan skip_all => 'GnuPG required.'
    unless eval 'use GnuPG::Interface; 1';
plan skip_all => 'gpg executable is required.'
    unless RT::Test->find_executable('gpg');

plan tests => 93;

use RT::ScripAction::SendEmail;

eval 'use GnuPG::Interface; 1' or plan skip_all => 'GnuPG required.';

RT::Test->set_mail_catcher;

RT->config->set( comment_address => 'general@example.com');
RT->config->set( correspond_address => 'general@example.com');
RT->config->set( default_search_result_format => qq{
   '<B><A HREF="__WebPath__/Ticket/Display.html?id=__id__">__id__</a></B>/TITLE:#',
   '<B><A HREF="__WebPath__/Ticket/Display.html?id=__id__">__subject__</a></B>/TITLE:subject',
   'OO-__owner_name__-O',
   'OR-__requestors__-O',
   'KO-__key_owner_name__-K',
   'KR-__key_requestors__-K',
   status});

use File::Spec ();
use Cwd;
use File::Temp qw(tempdir);
my $homedir = tempdir( CLEANUP => 1 );
use_ok('RT::Crypt::GnuPG');

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
        passphrase              => 'recipient',
        'no-permission-warning' => undef,
        'trust-model'           => 'always',
    }
);
RT->config->set( 'mail_plugins' => ['Auth::MailFrom', 'Auth::GnuPG'] );
RT::Test->import_gnupg_key('recipient@example.com', 'public');
RT::Test->import_gnupg_key('recipient@example.com', 'secret');
RT::Test->import_gnupg_key('general@example.com', 'public');
RT::Test->import_gnupg_key('general@example.com', 'secret');
RT::Test->import_gnupg_key('general@example.com.2', 'public');
RT::Test->import_gnupg_key('general@example.com.2', 'secret');

my $rtname = RT->config->get('rtname');
ok(my $user = RT::Model::User->new(current_user => RT->system_user));
ok($user->load('root'), "Loaded user 'root'");
$user->set_email('recipient@example.com');

my $queue = RT::Test->load_or_create_queue(
    name              => 'General',
    correspond_address => 'general@example.com',
);
ok $queue && $queue->id, 'loaded or created queue';
my $qid = $queue->id;

RT::Test->set_rights(
    principal => 'Everyone',
    right => ['CreateTicket', 'ShowTicket', 'SeeQueue', 'ModifyTicket'],
);

my ($baseurl, $m) = RT::Test->started_ok;
diag($baseurl) if $ENV{TEST_VERBOSE};
ok $m->login, 'logged in';

$m->get_ok("/Admin/Queues/Modify.html?id=$qid");
$m->form_with_fields('sign', 'encrypt');
$m->field(encrypt => 1);
$m->submit;

RT::Test->clean_caught_mails;

$m->goto_create_ticket( $queue );
$m->form_name('ticket_create');

$m->field('subject', 'Encryption test');
$m->field('content', 'Some content');
ok($m->value('encrypt', 2), "encrypt tick box is checked");
ok(!$m->value('sign', 2), "sign tick box is unchecked");
$m->submit;
is($m->status, 200, "request successful");

$m->get($baseurl); # ensure that the mail has been processed

my @mail = RT::Test->fetch_caught_mails;
ok(@mail, "got some mail");
$user->set_email('general@example.com');
for my $mail (@mail) {
    unlike $mail, qr/Some content/, "outgoing mail was encrypted";

    my ($content_type) = $mail =~ /^(Content-Type: .*)/m;
    my ($mime_version) = $mail =~ /^(MIME-Version: .*)/m;
    my $body = strip_headers($mail);

    $mail = << "MAIL";
Subject: RT mail sent back into RT
From: general\@example.com
To: recipient\@example.com
$mime_version
$content_type

$body
MAIL
 
    my ($status, $id) = RT::Test->send_via_mailgate($mail);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "got id of a newly created ticket - $id");

    my $tick = RT::Model::Ticket->new(current_user => RT->system_user );
    $tick->load( $id );
    ok ($tick->id, "loaded ticket #$id");

    is ($tick->subject,
        "RT mail sent back into RT",
        "Correct subject"
    );

    my $txn = $tick->transactions->first;
    my ($msg, @attachments) = @{$txn->attachments->items_array_ref};

    is( $msg->get_header('X-RT-Privacy'),
        'PGP',
        "RT's outgoing mail has crypto"
    );
    is( $msg->get_header('X-RT-Incoming-Encryption'),
        'Success',
        "RT's outgoing mail looks encrypted"
    );

    like($attachments[0]->content, qr/Some content/, "RT's mail includes copy of ticket text");
    like($attachments[0]->content, qr/$rtname/, "RT's mail includes this instance's name");
}

$m->get("$baseurl/Admin/Queues/Modify.html?id=$qid");
$m->form_with_fields('sign', 'encrypt');
$m->field(encrypt => undef);
$m->field(sign => 1);
$m->submit;

RT::Test->clean_caught_mails;

$m->goto_create_ticket( $queue );
$m->form_name('ticket_create');
$m->field('subject', 'Signing test');
$m->field('content', 'Some other content');
ok(!$m->value('encrypt', 2), "encrypt tick box is unchecked");
ok($m->value('sign', 2), "sign tick box is checked");
$m->submit;
is($m->status, 200, "request successful");

$m->get($baseurl); # ensure that the mail has been processed

@mail = RT::Test->fetch_caught_mails;
ok(@mail, "got some mail");
for my $mail (@mail) {
    like $mail, qr/Some other content/, "outgoing mail was not encrypted";
    like $mail, qr/-----BEGIN PGP SIGNATURE-----[\s\S]+-----END PGP SIGNATURE-----/, "data has some kind of signature";

    my ($content_type) = $mail =~ /^(Content-Type: .*)/m;
    my ($mime_version) = $mail =~ /^(MIME-Version: .*)/m;
    my $body = strip_headers($mail);

    $mail = << "MAIL";
Subject: More RT mail sent back into RT
From: general\@example.com
To: recipient\@example.com
$mime_version
$content_type

$body
MAIL
 
    my ($status, $id) = RT::Test->send_via_mailgate($mail);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "got id of a newly created ticket - $id");

    my $tick = RT::Model::Ticket->new(current_user => RT->system_user );
    $tick->load( $id );
    ok ($tick->id, "loaded ticket #$id");

    is ($tick->subject,
        "More RT mail sent back into RT",
        "Correct subject"
    );

    my $txn = $tick->transactions->first;
    my ($msg, @attachments) = @{$txn->attachments->items_array_ref};

    is( $msg->get_header('X-RT-Privacy'),
        'PGP',
        "RT's outgoing mail has crypto"
    );
    is( $msg->get_header('X-RT-Incoming-Encryption'),
        'Not encrypted',
        "RT's outgoing mail looks unencrypted"
    );
    is( $msg->get_header('X-RT-Incoming-Signature'),
        'general <general@example.com>',
        "RT's outgoing mail looks signed"
    );

    like($attachments[0]->content, qr/Some other content/, "RT's mail includes copy of ticket text");
    like($attachments[0]->content, qr/$rtname/, "RT's mail includes this instance's name");
}

$m->get("$baseurl/Admin/Queues/Modify.html?id=$qid");
$m->form_with_fields('sign', 'encrypt');
$m->field(encrypt => 1);
$m->field(sign => 1);
$m->submit;

RT::Test->clean_caught_mails;

$user->set_email('recipient@example.com');
$m->goto_create_ticket( $queue );
$m->form_name('ticket_create');
$m->field('subject', 'Crypt+Sign test');
$m->field('content', 'Some final? content');
ok($m->value('encrypt', 2), "encrypt tick box is checked");
ok($m->value('sign', 2), "sign tick box is checked");
$m->submit;
is($m->status, 200, "request successful");
$m->get($baseurl); # ensure that the mail has been processed

@mail = RT::Test->fetch_caught_mails;
ok(@mail, "got some mail");

$user->set_email('general@example.com');
for my $mail (@mail) {
    unlike $mail, qr/Some other content/, "outgoing mail was encrypted";

    my ($content_type) = $mail =~ /^(Content-Type: .*)/m;
    my ($mime_version) = $mail =~ /^(MIME-Version: .*)/m;
    my $body = strip_headers($mail);

    $mail = << "MAIL";
Subject: Final RT mail sent back into RT
From: general\@example.com
To: recipient\@example.com
$mime_version
$content_type

$body
MAIL
 
    my ($status, $id) = RT::Test->send_via_mailgate($mail);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "got id of a newly created ticket - $id");

    my $tick = RT::Model::Ticket->new(current_user => RT->system_user );
    $tick->load( $id );
    ok ($tick->id, "loaded ticket #$id");

    is ($tick->subject,
        "Final RT mail sent back into RT",
        "Correct subject"
    );

    my $txn = $tick->transactions->first;
    my ($msg, @attachments) = @{$txn->attachments->items_array_ref};

    is( $msg->get_header('X-RT-Privacy'),
        'PGP',
        "RT's outgoing mail has crypto"
    );
    is( $msg->get_header('X-RT-Incoming-Encryption'),
        'Success',
        "RT's outgoing mail looks encrypted"
    );
    is( $msg->get_header('X-RT-Incoming-Signature'),
        'general <general@example.com>',
        "RT's outgoing mail looks signed"
    );

    like($attachments[0]->content, qr/Some final\? content/, "RT's mail includes copy of ticket text");
    like($attachments[0]->content, qr/$rtname/, "RT's mail includes this instance's name");
}

RT::Test->fetch_caught_mails;

$m->goto_create_ticket( $queue );
$m->form_name('ticket_create');
$m->field('subject', 'Test crypt-off on encrypted queue');
$m->field('content', 'Thought you had me figured out didya');
$m->field(encrypt => undef, 2); # turn off encryption
ok(!$m->value('encrypt', 2), "encrypt tick box is now unchecked");
ok($m->value('sign', 2), "sign tick box is still checked");
$m->submit;
is($m->status, 200, "request successful");

$m->get($baseurl); # ensure that the mail has been processed
@mail = RT::Test->fetch_caught_mails;
ok(@mail, "got some mail");
for my $mail (@mail) {
    like $mail, qr/Thought you had me figured out didya/, "outgoing mail was unencrypted";

    my ($content_type) = $mail =~ /^(Content-Type: .*)/m;
    my ($mime_version) = $mail =~ /^(MIME-Version: .*)/m;
    my $body = strip_headers($mail);

    $mail = << "MAIL";
Subject: Post-final! RT mail sent back into RT
From: general\@example.com
To: recipient\@example.com
$mime_version
$content_type

$body
MAIL
 
    my ($status, $id) = RT::Test->send_via_mailgate($mail);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "got id of a newly created ticket - $id");

    my $tick = RT::Model::Ticket->new(current_user => RT->system_user );
    $tick->load( $id );
    ok ($tick->id, "loaded ticket #$id");

    is ($tick->subject,
        "Post-final! RT mail sent back into RT",
        "Correct subject"
    );

    my $txn = $tick->transactions->first;
    my ($msg, @attachments) = @{$txn->attachments->items_array_ref};

    is( $msg->get_header('X-RT-Privacy'),
        'PGP',
        "RT's outgoing mail has crypto"
    );
    is( $msg->get_header('X-RT-Incoming-Encryption'),
        'Not encrypted',
        "RT's outgoing mail looks unencrypted"
    );
    is( $msg->get_header('X-RT-Incoming-Signature'),
        'general <general@example.com>',
        "RT's outgoing mail looks signed"
    );

    like($attachments[0]->content, qr/Thought you had me figured out didya/, "RT's mail includes copy of ticket text");
    like($attachments[0]->content, qr/$rtname/, "RT's mail includes this instance's name");
}

sub strip_headers
{
    my $mail = shift;
    $mail =~ s/.*?\n\n//s;
    return $mail;
}

# now test the owner_nameKey and RequestorsKey fields
my $nokey = RT::Test->load_or_create_user(name => 'nokey', email => 'nokey@example.com');
$nokey->principal->grant_right(right => 'CreateTicket');
$nokey->principal->grant_right(right => 'OwnTicket');

my $tick = RT::Model::Ticket->new(current_user => RT->system_user );
$tick->create(subject => 'owner lacks pubkey', queue => 'general',
              owner => $nokey);
ok(my $id = $tick->id, 'created ticket for owner-without-pubkey');

$tick = RT::Model::Ticket->new(current_user => RT->system_user );
$tick->create(subject => 'owner has pubkey', queue => 'general',
              owner => 'root');
ok($id = $tick->id, 'created ticket for owner-with-pubkey');
my $mail = << "MAIL";
Subject: Nokey requestor
From: nokey\@example.com
To: general\@example.com

hello
MAIL
 
((my $status), $id) = RT::Test->send_via_mailgate($mail);
$m->warnings_like( qr/Recipient 'nokey\@example.com' is unusable/ );

is ($status >> 8, 0, "The mail gateway exited normally");
ok ($id, "got id of a newly created ticket - $id");
$tick = RT::Model::Ticket->new(current_user => RT->system_user );
$tick->load( $id );
ok ($tick->id, "loaded ticket #$id");
is ($tick->subject,
    "Nokey requestor",
    "Correct subject"
);

# test key selection
my $key1 = "EC1E81E7DC3DB42788FB0E4E9FA662C06DE22FC2";
my $key2 = "75E156271DCCF02DDD4A7A8CDF651FA0632C4F50";

$user->set_email('general@example.com');

ok($user = RT::Model::User->new(current_user => RT->system_user));
ok($user->load('root'), "Loaded user 'root'");
is($user->preferred_key, $key1, "preferred key is set correctly");
$m->get("$baseurl/Prefs/Other.html");
$m->content_like( qr/Preferred key/, "preferred key option shows up in preference");

# XXX: mech doesn't let us see the current value of the select, apparently
$m->content_like( qr/$key1/, "first key shows up in preferences");
$m->content_like( qr/$key2/, "second key shows up in preferences");
$m->content_like( qr/$key1.*?$key2/s, "first key shows up before the second");

$m->form_with_fields('preferred_key');
$m->select("preferred_key" => $key2);
$m->submit;

ok($user = RT::Model::User->new(current_user => RT->system_user));
ok($user->load('root'), "Loaded user 'root'");
is($user->preferred_key, $key2, "preferred key is set correctly to the new value");

$m->get("$baseurl/Prefs/Other.html");
$m->content_like( qr/Preferred key/, "preferred key option shows up in preference");

# XXX: mech doesn't let us see the current value of the select, apparently
$m->content_like( qr/$key2/, "second key shows up in preferences");
$m->content_like( qr/$key1/, "first key shows up in preferences");
$m->content_like( qr/$key2.*?$key1/s, "second key (now preferred) shows up before the first");

# test that the new fields work
$m->get("$baseurl/Search/Simple.html?q=General");
my $content = $m->content;
$content =~ s/&#40;/(/g;
$content =~ s/&#41;/)/g;

like($content, qr/OO-Nobody-O/, "original owner_name untouched");
like($content, qr/OO-nokey-O/, "original owner_name untouched");
like($content, qr/OO-root-O/, "original owner_name untouched");

#like($content, qr/OR-recipient\@example.com-O/, "original Requestors untouched");
like($content, qr/OR-nokey\@example.com-O/, "original Requestors untouched");

like($content, qr/KO-root-K/, "key_owner_name does not issue no-pubkey warning for recipient");
like($content, qr/KO-nokey \(no pubkey!\)-K/, "key_owner_name issues no-pubkey warning for root");
like($content, qr/KO-Nobody \(no pubkey!\)-K/, "key_owner_name issues no-pubkey warning for nobody");

#like($content, qr/KR-recipient\@example.com-K/, "key_requestors does not issue no-pubkey warning for recipient\@example.com");
like($content, qr/KR-general\@example.com-K/, "key_requestors does not issue no-pubkey warning for general\@example.com");
like($content, qr/KR-nokey\@example.com \(no pubkey!\)-K/, "key_requestors DOES issue no-pubkey warning for nokey\@example.com");

