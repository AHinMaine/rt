# BEGIN BPS TAGGED BLOCK {{{
#
# COPYRIGHT:
#
# This software is Copyright (c) 1996-2008 Best Practical Solutions, LLC
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
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.html.
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

RT::ScripAction::NotifyGroup - RT Action that sends notifications to groups and/or users

=head1 DESCRIPTION

RT action module that allow you to notify particular groups and/or users.
Distribution is shipped with C<rt-email-group-admin> script that
is command line tool for managing NotifyGroup scrip actions. For more
more info see its documentation.

=cut

package RT::ScripAction::NotifyGroup;

use strict;
use warnings;
use base qw(RT::ScripAction::Notify);

require RT::Model::User;
require RT::Model::Group;

=head1 METHODS

=head2 set_recipients

Sets the recipients of this message to Groups and/or Users.

=cut

sub set_recipients {
    my $self = shift;

    my $arg = $self->argument;

    my $old_arg = eval { Storable::thaw($arg) };
    unless ($@) {
        $arg = $self->__convert_old_arg($old_arg);
    }

    foreach ( $self->__split_arg($arg) ) {
        $self->_handle_argument($_);
    }

    my $creator = $self->transaction_obj->creator_obj->email();
    unless ($RT::NotifyActor) {
        @{ $self->{'To'} } = grep ( !/^\Q$creator\E$/, @{ $self->{'To'} } );
    }

    $self->{'seen_ueas'} = {};

    return 1;
}

sub _HandleArgument {
    my $self     = shift;
    my $instance = shift;

    my $obj = RT::Principal->new(RT->system_user);
    $obj->load($instance);
    unless ( $obj->id ) {
        Jifty->log->error("Couldn't load principal #$instance");
        return;
    }
    if ( $obj->disabled ) {
        Jifty->log->info("Principal #$instance is disabled => skip");
        return;
    }
    if ( !$obj->type ) {
        Jifty->log->crit("Principal #$instance has empty type");
    }
    elsif ( lc $obj->type eq 'user' ) {
        $self->__handle_user_argument( $obj->object );
    }
    elsif ( lc $obj->type eq 'group' ) {
        $self->__handle_group_argument( $obj->object );
    }
    else {
        Jifty->log->info("Principal #$instance has unsupported type");
    }
    return;
}

sub __HandleUserArgument {
    my $self = shift;
    my $obj  = shift;

    my $uea = $obj->email;
    unless ($uea) {
        Jifty->log->warn( "User #" . $obj->id . " has no email address" );
        return;
    }
    $self->__push_user_address($uea);
}

sub __HandleGroupArgument {
    my $self = shift;
    my $obj  = shift;

    my $members = $obj->user_members;
    while ( my $m = $members->next ) {
        $self->__handle_user_argument($m);
    }
}

sub __SplitArg {
    return split /[^0-9]+/, $_[1];
}

sub __ConvertOldArg {
    my $self = shift;
    my $arg  = shift;
    my @res;
    foreach my $r ( @{$arg} ) {
        my $obj;
        next unless $r->{'Type'};
        if ( lc $r->{'Type'} eq 'user' ) {
            $obj = RT::Model::User->new(RT->system_user);
        }
        elsif ( lc $r->{'Type'} eq 'user' ) {
            $obj = RT::Model::Group->new(RT->system_user);
        }
        else {
            next;
        }
        $obj->load( $r->{'instance'} );
        my $id = $obj->id;
        next unless ($id);

        push @res, $id;
    }

    return join ';', @res;
}

sub __PushUserAddress {
    my $self = shift;
    my $uea  = shift;
    push @{ $self->{'To'} }, $uea unless $self->{'seen_ueas'}{$uea}++;
    return;
}

=head1 AUTHOR

Ruslan U. Zakirov E<lt>ruz@bestpractical.comE<gt>

L<RT::ScripAction::NotifyGroupAsComment>, F<rt-email-group-admin>

=cut

1;
