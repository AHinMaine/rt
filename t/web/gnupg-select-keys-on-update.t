#!/usr/bin/perl -w
use strict;
use warnings;

use Test::More;
use RT::Test strict => 1;

plan skip_all => 'GnuPG required.'
    unless eval 'use GnuPG::Interface; 1';
plan skip_all => 'gpg executable is required.'
    unless RT::Test->find_executable('gpg');

plan tests => 69;

use RT::ScripAction::SendEmail;
use File::Temp qw(tempdir);

RT::Test->set_mail_catcher;

use_ok('RT::Crypt::GnuPG');

RT->config->set(
    gnupg => {
        enable                   => 1,
        outgoing_messages_format => 'RFC',
    }
);

RT->config->set(
    gnupg_options => {
        homedir                 => scalar tempdir( CLEANUP => 0 ),
        passphrase              => 'rt-test',
        'no-permission-warning' => undef,
    }
);
diag "GnuPG --homedir ". RT->config->get('gnupg_options')->{'homedir'} if $ENV{TEST_VERBOSE};

RT->config->set( 'mail_plugins' => [ 'Auth::MailFrom', 'Auth::GnuPG' ] );

my $queue = RT::Test->load_or_create_queue(
    name              => 'Regression',
    correspond_address => 'rt-recipient@example.com',
    comment_address    => 'rt-recipient@example.com',
);
ok $queue && $queue->id, 'loaded or created queue';

RT::Test->set_rights(
    principal => 'Everyone',
    right => ['CreateTicket', 'ShowTicket', 'SeeQueue', 'ReplyToTicket', 'ModifyTicket'],
);

my ($baseurl, $m) = RT::Test->started_ok;
ok $m->login, 'logged in';


my $tid;
{
    my $ticket = RT::Model::Ticket->new(current_user => RT->system_user );
    ($tid) = $ticket->create(
        subject   => 'test',
        queue     => $queue->id,
    );
    ok $tid, 'ticket created';
}

diag "check that signing doesn't work if there is no key" if $ENV{TEST_VERBOSE};
{
    RT::Test->clean_caught_mails;

    ok $m->goto_ticket( $tid ), "UI -> ticket #$tid";
    $m->follow_link_ok( { text => 'Reply' }, 'ticket -> reply' );
    $m->form_number(3);
    $m->tick( sign => 1 );
    $m->field( update_cc => 'rt-test@example.com' );
    $m->field( update_content => 'Some content' );
    $m->click('submit_ticket');
    $m->content_like(
        qr/unable to sign outgoing email messages/i,
        'problems with passphrase'
    );
    $m->warnings_like( qr/secret key not available/, 'got secret key not available warning' );

    my @mail = RT::Test->fetch_caught_mails;
    ok !@mail, 'there are no outgoing emails';
}

{
    RT::Test->import_gnupg_key('rt-recipient@example.com');
    RT::Test->trust_gnupg_key('rt-recipient@example.com');
    my %res = RT::Crypt::GnuPG::get_keys_info('rt-recipient@example.com');
    is $res{'info'}[0]{'trust_terse'}, 'ultimate', 'ultimately trusted key';
}

diag "check that things don't work if there is no key" if $ENV{TEST_VERBOSE};
{
    RT::Test->clean_caught_mails;

    ok $m->goto_ticket( $tid ), "UI -> ticket #$tid";
    $m->follow_link_ok( { text => 'Reply' }, 'ticket -> reply' );
    $m->form_number(3);
    $m->tick( encrypt => 1 );
    $m->field( update_cc => 'rt-test@example.com' );
    $m->field( update_content => 'Some content' );
    $m->click('submit_ticket');
    $m->content_like(
        qr/You are going to encrypt outgoing email messages/i,
        'problems with keys'
    );
    $m->content_like(
        qr/There is no key suitable for encryption/i,
        'problems with keys'
    );

    my $form = $m->form_number(3);
    ok !$form->find_input( 'UseKey-rt-test@example.com' ), 'no key selector';

    my @mail = RT::Test->fetch_caught_mails;
    ok !@mail, 'there are no outgoing emails';
}


diag "import first key of rt-test\@example.com" if $ENV{TEST_VERBOSE};
my $fpr1 = '';
{
    RT::Test->import_gnupg_key('rt-test@example.com', 'public');
    my %res = RT::Crypt::GnuPG::get_keys_info('rt-test@example.com');
    is $res{'info'}[0]{'trust_level'}, 0, 'is not trusted key';
    $fpr1 = $res{'info'}[0]{'fingerprint'};
}

diag "check that things still doesn't work if key is not trusted" if $ENV{TEST_VERBOSE};
{
    RT::Test->clean_caught_mails;

    ok $m->goto_ticket( $tid ), "UI -> ticket #$tid";
    $m->follow_link_ok( { text => 'Reply' }, 'ticket -> reply' );
    $m->form_number(3);
    $m->tick( encrypt => 1 );
    $m->field( update_cc => 'rt-test@example.com' );
    $m->field( update_content => 'Some content' );
    $m->click('submit_ticket');
    $m->content_like(
        qr/You are going to encrypt outgoing email messages/i,
        'problems with keys'
    );
    $m->content_like(
        qr/There is one suitable key, but trust level is not set/i,
        'problems with keys'
    );

    my $form = $m->form_number(3);
    ok my $input = $form->find_input( 'UseKey-rt-test@example.com' ), 'found key selector';
    is scalar $input->possible_values, 1, 'one option';

    $m->select( 'UseKey-rt-test@example.com' => $fpr1 );
    $m->click('submit_ticket');
    $m->content_like(
        qr/You are going to encrypt outgoing email messages/i,
        'problems with keys'
    );
    $m->content_like(
        qr/Selected key either is not trusted/i,
        'problems with keys'
    );

    my @mail = RT::Test->fetch_caught_mails;
    ok !@mail, 'there are no outgoing emails';
}

diag "import a second key of rt-test\@example.com" if $ENV{TEST_VERBOSE};
my $fpr2 = '';
{
    RT::Test->import_gnupg_key('rt-test@example.com.2', 'public');
    my %res = RT::Crypt::GnuPG::get_keys_info('rt-test@example.com');
    is $res{'info'}[1]{'trust_level'}, 0, 'is not trusted key';
    $fpr2 = $res{'info'}[2]{'fingerprint'};
}

diag "check that things still doesn't work if two keys are not trusted" if $ENV{TEST_VERBOSE};
{
    RT::Test->clean_caught_mails;

    ok $m->goto_ticket( $tid ), "UI -> ticket #$tid";
    $m->follow_link_ok( { text => 'Reply' }, 'ticket -> reply' );
    $m->form_number(3);
    $m->tick( encrypt => 1 );
    $m->field( update_cc => 'rt-test@example.com' );
    $m->field( update_content => 'Some content' );
    $m->click('submit_ticket');
    $m->content_like(
        qr/You are going to encrypt outgoing email messages/i,
        'problems with keys'
    );
    $m->content_like(
        qr/There are several keys suitable for encryption/i,
        'problems with keys'
    );

    my $form = $m->form_number(3);
    ok my $input = $form->find_input( 'UseKey-rt-test@example.com' ), 'found key selector';
    is scalar $input->possible_values, 2, 'two options';

    $m->select( 'UseKey-rt-test@example.com' => $fpr1 );
    $m->click('submit_ticket');
    $m->content_like(
        qr/You are going to encrypt outgoing email messages/i,
        'problems with keys'
    );
    $m->content_like(
        qr/Selected key either is not trusted/i,
        'problems with keys'
    );

    my @mail = RT::Test->fetch_caught_mails;
    ok !@mail, 'there are no outgoing emails';
}

{
    RT::Test->lsign_gnupg_key( $fpr1 );
    my %res = RT::Crypt::GnuPG::get_keys_info('rt-test@example.com');
    ok $res{'info'}[0]{'trust_level'} > 0, 'trusted key';
    is $res{'info'}[1]{'trust_level'}, 0, 'is not trusted key';
}

diag "check that we see key selector even if only one key is trusted but there are more keys" if $ENV{TEST_VERBOSE};
{
    RT::Test->clean_caught_mails;

    ok $m->goto_ticket( $tid ), "UI -> ticket #$tid";
    $m->follow_link_ok( { text => 'Reply' }, 'ticket -> reply' );
    $m->form_number(3);
    $m->tick( encrypt => 1 );
    $m->field( update_cc => 'rt-test@example.com' );
    $m->field( update_content => 'Some content' );
    $m->click('submit_ticket');
    $m->content_like(
        qr/You are going to encrypt outgoing email messages/i,
        'problems with keys'
    );
    $m->content_like(
        qr/There are several keys suitable for encryption/i,
        'problems with keys'
    );

    my $form = $m->form_number(3);
    ok my $input = $form->find_input( 'UseKey-rt-test@example.com' ), 'found key selector';
    is scalar $input->possible_values, 2, 'two options';

    my @mail = RT::Test->fetch_caught_mails;
    ok !@mail, 'there are no outgoing emails';
}

diag "check that key selector works and we can select trusted key" if $ENV{TEST_VERBOSE};
{
    RT::Test->clean_caught_mails;

    ok $m->goto_ticket( $tid ), "UI -> ticket #$tid";
    $m->follow_link_ok( { text => 'Reply' }, 'ticket -> reply' );
    $m->form_number(3);
    $m->tick( encrypt => 1 );
    $m->field( update_cc => 'rt-test@example.com' );
    $m->field( update_content => 'Some content' );
    $m->click('submit_ticket');
    $m->content_like(
        qr/You are going to encrypt outgoing email messages/i,
        'problems with keys'
    );
    $m->content_like(
        qr/There are several keys suitable for encryption/i,
        'problems with keys'
    );

    my $form = $m->form_number(3);
    ok my $input = $form->find_input( 'UseKey-rt-test@example.com' ), 'found key selector';
    is scalar $input->possible_values, 2, 'two options';

    $m->select( 'UseKey-rt-test@example.com' => $fpr1 );
    $m->click('submit_ticket');
    $m->content_like( qr/Message recorded/i, 'Message recorded' );

    my @mail = RT::Test->fetch_caught_mails;
    ok @mail, 'there are some emails';
    check_text_emails( { encrypt => 1 }, @mail );
}

diag "check encrypting of attachments" if $ENV{TEST_VERBOSE};
{
    RT::Test->clean_caught_mails;

    ok $m->goto_ticket( $tid ), "UI -> ticket #$tid";
    $m->follow_link_ok( { text => 'Reply' }, 'ticket -> reply' );
    $m->form_number(3);
    $m->tick( encrypt => 1 );
    $m->field( update_cc => 'rt-test@example.com' );
    $m->field( update_content => 'Some content' );
    $m->field( attach => $0 );
    $m->click('submit_ticket');
    $m->content_like(
        qr/You are going to encrypt outgoing email messages/i,
        'problems with keys'
    );
    $m->content_like(
        qr/There are several keys suitable for encryption/i,
        'problems with keys'
    );

    my $form = $m->form_number(3);
    ok my $input = $form->find_input( 'UseKey-rt-test@example.com' ), 'found key selector';
    is scalar $input->possible_values, 2, 'two options';

    $m->select( 'UseKey-rt-test@example.com' => $fpr1 );
    $m->click('submit_ticket');
    $m->content_like( qr/Message recorded/i, 'Message recorded' );

    my @mail = RT::Test->fetch_caught_mails;
    ok @mail, 'there are some emails';
    check_text_emails( { encrypt => 1, attachment => 1 }, @mail );
}

sub check_text_emails {
    my %args = %{ shift @_ };
    my @mail = @_;

    ok scalar @mail, "got some mail";
    for my $mail (@mail) {
        for my $type ('email', 'attachment') {
            next if $type eq 'attachment' && !$args{'attachment'};

            my $content = $type eq 'email'
                        ? "Some content"
                        : "Attachment content";

            if ( $args{'encrypt'} ) {
                unlike $mail, qr/$content/, "outgoing $type was encrypted";
            } else {
                like $mail, qr/$content/, "outgoing $type was not encrypted";
            } 

            next unless $type eq 'email';

            if ( $args{'sign'} && $args{'encrypt'} ) {
                like $mail, qr/BEGIN PGP MESSAGE/, 'outgoing email was signed';
            } elsif ( $args{'sign'} ) {
                like $mail, qr/SIGNATURE/, 'outgoing email was signed';
            } else {
                unlike $mail, qr/SIGNATURE/, 'outgoing email was not signed';
            }
        }
    }
}

