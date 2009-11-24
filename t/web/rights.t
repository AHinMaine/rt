#!/usr/bin/perl -w
use strict;
use warnings;

use RT::Test strict => 1; use Test::More tests => 14;


my ($baseurl, $m) = RT::Test->started_ok;
ok $m->login, "logged in";
$m->follow_link_ok( text => 'Configuration' );
$m->follow_link_ok( text => 'Global' );
$m->follow_link_ok( text => 'Group rights' );


sub get_rights {
    my $agent = shift;
    my $principal_id = shift;
    my $object = shift;
    $agent->form_number(3);
    my @inputs = $agent->current_form->find_input("revoke_right-$principal_id-$object");
    my @Rights = sort grep $_, map $_->possible_values, grep $_, @inputs;
    return @Rights;
};

diag "load Everyone group" if $ENV{'TEST_VERBOSE'};
my ($everyone, $everyone_gid);
{
    $everyone = RT::Model::Group->new(current_user => RT->system_user );
    $everyone->load_system_internal('Everyone');
    ok($everyone_gid = $everyone->id, "loaded 'everyone' group");
}

diag "revoke all global rights from Everyone group" if $ENV{'TEST_VERBOSE'};
my @has = get_rights( $m, $everyone_gid, 'RT::System-1' );
if ( @has ) {
    $m->form_number(3);
    $m->tick("revoke_right-$everyone_gid-RT::System-1", $_) foreach @has;
    $m->submit;
    
    is_deeply([get_rights( $m, $everyone_gid, 'RT::System-1' )], [], 'deleted all rights' );
} else {
    ok(1, 'the group has no global rights');
}

diag "grant SuperUser right to everyone" if $ENV{'TEST_VERBOSE'};
{
    $m->form_number(3);
    $m->select("grant_right-$everyone_gid-RT::System-1", ['SuperUser']);
    $m->submit;

    $m->content_contains('Right granted', 'got message');
    RT::Model::Principal::invalidate_acl_cache();
    ok($everyone->principal->has_right( right => 'SuperUser', object => RT->system ), 'group has right');
    is_deeply( [get_rights( $m, $everyone_gid, 'RT::System-1' )], ['SuperUser'], 'granted SuperUser right' );
}

diag "revoke the right" if $ENV{'TEST_VERBOSE'};
{
    $m->form_number(3);
    $m->tick("revoke_right-$everyone_gid-RT::System-1", 'SuperUser');
    $m->submit;

    $m->content_contains('Right revoked', 'got message');
    RT::Model::Principal::invalidate_acl_cache();
    ok(!$everyone->principal->has_right( right => 'SuperUser', object => RT->system ), 'group has no right');
    is_deeply( [get_rights( $m, $everyone_gid, 'RT::System-1' )], [], 'revoked SuperUser right' );
}


diag "return rights the group had in the beginning" if $ENV{'TEST_VERBOSE'};
if ( @has ) {
    $m->form_number(3);
    $m->select("grant_right-$everyone_gid-RT::System-1", \@has);
    $m->submit;

    $m->content_contains('right Granted', 'got message');
    is_deeply(
        [ get_rights( $m, $everyone_gid, 'RT::System-1' ) ],
        [ @has ],
        'returned back all rights'
    );
} else {
    ok(1, 'the group had no global rights, so nothing to return');
}

