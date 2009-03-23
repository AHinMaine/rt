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

=head1 name 

RT::System

=head1 description

RT::System is a simple global object used as a focal point for things
that are system-wide.

It works sort of like an RT::Record, except it's really a single object that has
an id of "1" when instantiated.

This gets used by the ACL system so that you can have rights for the scope "RT::System"

In the future, there will probably be other API goodness encapsulated here.

=cut

use warnings;
use strict;

package RT::System;
use base qw/RT::Record/;

use RT::Model::ACECollection;

# System rights are rights granted to the whole system
# XXX TODO Can't localize these outside of having an object around.
our $RIGHTS = {
    SuperUser              => 'Do anything and everything',                                             # loc_pair
    AdminUsers             => 'Create, delete and modify users',                                        # loc_pair
    ModifySelf             => "Modify one's own RT account",                                            # loc_pair
    ShowConfigTab          => "show Configuration tab",                                                 # loc_pair
    ShowApprovalsTab       => "show Approvals tab",    # loc_pair
    
    LoadSavedSearch        => "allow loading of saved searches",                                        # loc_pair
    CreateSavedSearch      => "allow creation of saved searches",                                       # loc_pair
};

# Tell RT::Model::ACE that this sort of object can get acls granted
$RT::Model::ACE::OBJECT_TYPES{'RT::System'} = 1;

foreach my $right ( keys %{$RIGHTS} ) {
    $RT::Model::ACE::LOWERCASERIGHTNAMES{ lc $right } = $right;
}

=head2 available_rights

Returns a hash of available rights for this object.
The keys are the right names and the values are a
description of what the rights do.

This method as well returns rights of other RT objects,
like L<RT::Model::Queue> or L<RT::Model::Group>. To allow users to apply
those rights globally.

=cut

use RT::Model::CustomField;
use RT::Model::Queue;
use RT::Model::Group;

sub available_rights {
    my $self = shift;

    my $queue = RT::Model::Queue->new( current_user => RT->system_user );
    my $group = RT::Model::Group->new( current_user => RT->system_user );
    my $cf = RT::Model::CustomField->new( current_user => RT->system_user );

    my $qr = $queue->available_rights();
    my $gr = $group->available_rights();
    my $cr = $cf->available_rights();

    # Build a merged list of all system wide rights, queue rights and group rights.
    my %Rights = ( %{$RIGHTS}, %{$gr}, %{$qr}, %{$cr} );
    return ( \%Rights );
}

=head2 id

Returns RT::System's id. It's 1. 

=cut

*Id = \&id;
sub id      { return 1 }
sub load    { return 1 }
sub name    { return 'RT System' }
sub __set   { return 0 }
sub __value { return 0 }
sub create  { return 0 }
sub delete  { return 0 }

sub subject_tag {
    my $self  = shift;
    my $queue = shift;

    my $map = $self->first_attribute('BrandedSubjectTag');
    $map = $map->content if $map;
    return $queue ? undef : () unless $map;

    return $map->{ $queue->id } if $queue;

    my %seen = ();
    return grep !$seen{ lc $_ }++, values %$map;
}

1;
