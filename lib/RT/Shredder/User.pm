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
use RT::Model::User ();

package RT::Model::User;

use strict;
use warnings;
use warnings FATAL => 'redefine';

use RT::Shredder::Constants;
use RT::Shredder::Exceptions;
use RT::Shredder::Dependencies;

my @OBJECTS = qw(
    AttachmentCollection
    CachedGroupMemberCollection
    CustomFieldCollection
    CustomFieldValueCollection
    GroupMemberCollection
    GroupCollection
    LinkCollection
    PrincipalCollection
    QueueCollection
    ScripActionCollection
    ScripConditionCollection
    TemplateCollection
    ObjectCustomFieldValueCollection
    TicketCollection
    TransactionCollection
    UserCollection
);

sub __depends_on {
    my $self = shift;
    my %args = (
        shredder     => undef,
        dependencies => undef,
        @_,
    );
    my $deps = $args{'dependencies'};
    my $list = [];

    # Principal
    $deps->_push_dependency(
        base_object   => $self,
        flags         => DEPENDS_ON | WIPE_AFTER,
        target_object => $self->principal,
        shredder      => $args{'shredder'}
    );

    # ACL equivalence group
    # don't use load_acl_equivalence_group cause it may not exists any more
    my $objs = RT::Model::GroupCollection->new( current_user => $self->current_user );
    $objs->limit( column => 'domain',   value => 'ACLEquivalence' );
    $objs->limit( column => 'instance', value => $self->id );
    push( @$list, $objs );

    # Cleanup user's membership
    $objs = RT::Model::GroupMemberCollection->new( current_user => $self->current_user );
    $objs->limit( column => 'member_id', value => $self->id );
    push( @$list, $objs );

    $deps->_push_dependencies(
        base_object    => $self,
        flags          => DEPENDS_ON,
        target_objects => $list,
        shredder       => $args{'shredder'}
    );

    # TODO: Almost all objects has creator, last_updated_by and etc. fields
    # which are references on users(Principal actualy)
    my @var_objs;
    foreach (@OBJECTS) {
        my $class = "RT::Model::$_";
        foreach my $method (qw(creator last_updated_by)) {
            my $objs = $class->new;
            next unless $objs->new_item->can($method);
            $objs->limit( column => $method, value => $self->id );
            push @var_objs, $objs;
        }
    }
    $deps->_push_dependencies(
        base_object    => $self,
        flags          => DEPENDS_ON | VARIABLE,
        target_objects => \@var_objs,
        shredder       => $args{'shredder'}
    );

    return $self->SUPER::__depends_on(%args);
}

sub __relates {
    my $self = shift;
    my %args = (
        shredder     => undef,
        dependencies => undef,
        @_,
    );
    my $deps = $args{'dependencies'};
    my $list = [];

    # Principal
    my $obj = $self->principal;
    if ( $obj && defined $obj->id ) {
        push( @$list, $obj );
    } else {
        my $rec = $args{'shredder'}->get_record( object => $self );
        $self = $rec->{'object'};
        $rec->{'state'} |= INVALID;
        $rec->{'description'} = "Have no related ACL equivalence Group object";
    }

    $obj = RT::Model::Group->new( current_user => RT->system_user );
    $obj->load_acl_equivalence_group( $self->principal );
    if ( $obj && defined $obj->id ) {
        push( @$list, $obj );
    } else {
        my $rec = $args{'shredder'}->get_record( object => $self );
        $self = $rec->{'object'};
        $rec->{'state'} |= INVALID;
        $rec->{'description'} = "Have no related Principal #" . $self->id . " object";
    }

    $deps->_push_dependencies(
        base_object    => $self,
        flags          => RELATES,
        target_objects => $list,
        shredder       => $args{'shredder'}
    );
    return $self->SUPER::__Relates(%args);
}

sub before_wipeout {
    my $self = shift;
    if ( $self->name =~ /^(RT_System|Nobody)$/ ) {
        RT::Shredder::Exception::Info->throw('Systemobject');
    }
    return $self->SUPER::before_wipeout(@_);
}

1;
