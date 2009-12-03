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
use RT::Record ();

package RT::Record;

use strict;
use warnings;
use warnings FATAL => 'redefine';

use RT::Shredder::Constants;
use RT::Shredder::Exceptions;

=head2 _as_string

Returns string in format Classname-object_id.

=cut

sub _as_string { return ref( $_[0] ) . "-" . $_[0]->id }

=head2 _as_insert_query

Returns INSERT query string that duplicates current record and
can be used to insert record back into DB after delete.

=cut

sub _as_insert_query {
    my $self = shift;

    my $dbh = Jifty->handle->dbh;

    my $res    = "INSERT INTO " . $dbh->quote_identifier( $self->table );
    my $values = $self->{'values'};
    $res .= "(" . join( ",", map { $dbh->quote_identifier($_) } sort keys %$values ) . ")";
    $res .= " VALUES";
    $res .= "(" . join( ",", map { $dbh->quote( $values->{$_} ) } sort keys %$values ) . ")";
    $res .= ";";

    return $res;
}

sub before_wipeout { return 1 }

=head2 dependencies

Returns L<RT::Shredder::Dependencies> object.

=cut

sub dependencies {
    my $self = shift;
    my %args = (
        shredder => undef,
        flags    => DEPENDS_ON,
        @_,
    );

    unless ( $self->id ) {
        RT::Shredder::Exception->throw('object is not loaded');
    }

    my $deps = RT::Shredder::Dependencies->new();
    if ( $args{'flags'} & DEPENDS_ON ) {
        $self->__depends_on( %args, dependencies => $deps );
    }
    return $deps;
}

sub __depends_on {
    my $self = shift;
    my %args = (
        shredder     => undef,
        dependencies => undef,
        @_,
    );
    my $deps = $args{'dependencies'};
    my $list = [];

    # object custom field values
    my $objs = $self->custom_field_values;
    $objs->{'find_expired_rows'} = 1;
    push( @$list, $objs );

    # object attributes
    $objs = $self->attributes;
    push( @$list, $objs );

    # Transactions
    $objs = RT::Model::TransactionCollection->new;
    $objs->limit( column => 'object_type', value => ref $self );
    $objs->limit( column => 'object_id',   value => $self->id );
    push( @$list, $objs );

    # Links
    if ( $self->can('_Links') ) {

        # XXX: We don't use Links->next as it's dies when object
        #      is linked to object that doesn't exist
        #      also, ->next skip links to deleted tickets :(
        foreach (qw(base target)) {
            my $objs = $self->_links($_);
            $objs->_do_search;
            push @$list, $objs->items_array_ref;
        }
    }

    # ACE records
    $objs = RT::Model::ACECollection->new;
    $objs->limit_to_object($self);
    push( @$list, $objs );

    $deps->_push_dependencies(
        base_object    => $self,
        flags          => DEPENDS_ON,
        target_objects => $list,
        shredder       => $args{'shredder'}
    );
    return;
}

# implement proxy method because some RT classes
# override Delete method
sub __wipeout {
    my $self = shift;
    my $msg  = $self->_as_string . " wiped out";
    $self->SUPER::delete;
    Jifty->log->debug($msg);
    return;
}

1;
