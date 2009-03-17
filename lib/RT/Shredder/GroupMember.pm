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
use RT::Model::GroupMember ();

package RT::Model::GroupMember;

use strict;
use warnings;
use warnings FATAL => 'redefine';

use RT::Shredder::Constants;
use RT::Shredder::Exceptions;
use RT::Shredder::Dependencies;

# No dependencies that should be deleted with record

sub __depends_on {
    my $self = shift;
    my %args = (
        shredder     => undef,
        dependencies => undef,
        @_,
    );
    my $deps = $args{'dependencies'};
    my $list = [];

    my $objs = RT::Model::CachedGroupMemberCollection->new( current_user => $self->current_user );
    $objs->limit( column => 'member_id',           value => $self->member_id );
    $objs->limit( column => 'immediate_parent', value => $self->group_id );
    push( @$list, $objs );


    $deps->_push_dependencies(
        base_object    => $self,
        flags          => DEPENDS_ON,
        target_objects => $list,
        shredder       => $args{'shredder'}
    );

    my $group = $self->group_obj->object;

    # XXX: If we delete member of the ticket owner role group then we should also
    # fix ticket object, but only if we don't plan to delete group itself!
    unless ( lc( $group->type || '' ) eq 'owner'
        && lc( $group->domain || '' ) eq 'rt::model::ticket-role' )
    {
        return $self->SUPER::__depends_on(%args);
    }

    # we don't delete group, so we have to fix Ticket and Group
    $deps->_push_dependencies(
        base_object    => $self,
        flags          => DEPENDS_ON | VARIABLE,
        target_objects => $group,
        shredder       => $args{'shredder'}
    );
    $args{'shredder'}->put_resolver(
        base_class   => ref $self,
        target_class => ref $group,
        code         => sub {
            my %args  = (@_);
            my $group = $args{'target_object'};
            return
                if $args{'shredder'}->get_state( object => $group ) & ( WIPED | IN_WIPING );
            return unless lc( $group->type || '' ) eq 'owner';
            return
                unless lc( $group->domain || '' ) eq 'rt::model::ticket-role';

            return if $group->members->count > 1;

            my $group_member = $args{'base_object'};

            if ( $group_member->member_obj->id == RT->nobody->id ) {
                RT::Shredder::Exception->throw("Couldn't delete Nobody from owners role group");
            }

            my ( $status, $msg ) = $group->add_member( RT->nobody->id );
            RT::Shredder::Exception->throw($msg) unless $status;

            my $ticket = RT::Model::Ticket->new( current_user => $group->current_user );
            $ticket->load( $group->instance );
            RT::Shredder::Exception->throw("Couldn't load ticket")
                unless $ticket->id;

            ( $status, $msg ) = $ticket->_set(
                column => 'owner',
                value  => RT->nobody->id,
            );
            RT::Shredder::Exception->throw($msg) unless $status;

            return;
        },
    );

    return $self->SUPER::__depends_on(%args);
}

#TODO: If we plan write export tool we also should fetch parent groups
# now we only wipeout things.

sub __relates {
    my $self = shift;
    my %args = (
        shredder     => undef,
        dependencies => undef,
        @_,
    );
    my $deps = $args{'dependencies'};
    my $list = [];

    my $obj = $self->member_obj;
    if ( $obj && $obj->id ) {
        push( @$list, $obj );
    } else {
        my $rec = $args{'shredder'}->get_record( object => $self );
        $self = $rec->{'object'};
        $rec->{'state'} |= INVALID;
        $rec->{'description'} = "Have no related Principal #" . $self->member_id . " object.";
    }

    $obj = $self->group_obj;
    if ( $obj && $obj->id ) {
        push( @$list, $obj );
    } else {
        my $rec = $args{'shredder'}->get_record( object => $self );
        $self = $rec->{'object'};
        $rec->{'state'} |= INVALID;
        $rec->{'description'} = "Have no related Principal #" . $self->group_id . " object.";
    }

    $deps->_push_dependencies(
        base_object    => $self,
        flags          => RELATES,
        target_objects => $list,
        shredder       => $args{'shredder'}
    );
    return $self->SUPER::__Relates(%args);
}

1;
