#!/usr/bin/perl
use strict;
use warnings;
use RT::Test; use Test::More tests => 9;


use RT::Interface::Email;

# normal use case, regexp set to rtname
RT->config->set( rtname => "site" );
RT->config->set( EmailSubjectTagRegex => 'site' );
RT->config->set( rtname => undef );
is(RT::Interface::Email::parse_ticket_id("[site #123] test"), 123);
is(RT::Interface::Email::parse_ticket_id("[othersite #123] test"), undef);

# oops usecase, where the regexp is scragged
RT->config->set( rtname => "site" );
RT->config->set( EmailSubjectTagRegex => undef );
is(RT::Interface::Email::parse_ticket_id("[site #123] test"), 123);
is(RT::Interface::Email::parse_ticket_id("[othersite #123] test"), undef);

# set to a simple regexp. NOTE: we no longer match "site"
RT->config->set( rtname => "site");
RT->config->set( EmailSubjectTagRegex => 'newsite');
is(RT::Interface::Email::parse_ticket_id("[site #123] test"), undef);
is(RT::Interface::Email::parse_ticket_id("[newsite #123] test"), 123);

# set to a more complex regexp
RT->config->set( rtname => "site" );
RT->config->set( EmailSubjectTagRegex => 'newsite|site' );
is(RT::Interface::Email::parse_ticket_id("[site #123] test"), 123);
is(RT::Interface::Email::parse_ticket_id("[newsite #123] test"), 123);
is(RT::Interface::Email::parse_ticket_id("[othersite #123] test"), undef);

