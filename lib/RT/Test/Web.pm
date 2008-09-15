# BEGIN BPS TAGGED BLOCK {{{
#
# COPYRIGHT:
#
# This software is Copyright (c) 1996-2007 Best Practical Solutions, LLC
#                                          <jesse@bestpractical.com>
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
package RT::Test::Web;

use strict;
use warnings;

use base qw(Jifty::Test::WWW::Mechanize);

require RT::Test;
require Test::More;

sub get_ok {
    my $self = shift;
    my $url  = shift;
    if ( $url =~ m{^/} ) {
        $url = $self->rt_base_url . $url;
    }
    return $self->SUPER::get_ok( $url, @_ );
}

sub rt_base_url {
    return $RT::Test::existing_server if $RT::Test::existing_server;
    return $RT::Test::server_url      if $RT::Test::server_url;
}

sub login {
    my $self = shift;
    my $user = shift || 'root';
    my $pass = shift || 'password';

    my $url = $self->rt_base_url;

    $self->get( $url . "/logout" );
    $self->get($url);

    my $moniker = $self->moniker_for('RT::Action::Login');

    $self->fill_in_action( $moniker, username => $user, password => $pass );
    $self->submit();
    unless ( $self->status == 200 ) {
        Test::More::diag( "error: status is " . $self->status );
        return 0;
    }
    unless ( $self->content =~ qr/Logout/i ) {
        Test::More::diag("error: page has no Logout");
        return 0;
    }
    return 1;
}

sub goto_ticket {
    my $self = shift;
    my $id   = shift;
    unless ( $id && int $id ) {
        Test::More::diag( "error: wrong id " . defined $id ? $id : '(undef)' );
        return 0;
    }

    my $url = $self->rt_base_url;
    $url .= "/Ticket/Display.html?id=$id";
    $self->get($url);
    unless ( $self->status == 200 ) {
        Test::More::diag( "error: status is " . $self->status );
        return 0;
    }
    return 1;
}

sub goto_create_ticket {
    my $self  = shift;
    my $queue = shift;

    my $id;
    if ( ref $queue ) {
        $id = $queue->id;
    } elsif ( $queue =~ /^\d+$/ ) {
        $id = $queue;
    } else {
        die "not yet implemented";
    }

    $self->get('/');
    $self->form_name('create_ticket_in_queue');
    $self->select( 'queue', $id );
    $self->submit;

    return 1;
}

1;
