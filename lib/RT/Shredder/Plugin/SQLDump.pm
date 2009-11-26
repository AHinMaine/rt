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
package RT::Shredder::Plugin::SQLDump;

use strict;
use warnings;

use base qw(RT::Shredder::Plugin::Base::Dump);
use RT::Shredder;

sub applies_to_states { return 'after wiping dependencies' }

sub support_args {
    my $self = shift;
    return $self->SUPER::support_args, qw(file_name from_storage);
}

sub test_args {
    my $self = shift;
    my %args = @_;
    $args{'from_storage'} = 1 unless defined $args{'from_storage'};
    my $file = $args{'file_name'} = RT::Shredder->get_file_name(
        file_name     => $args{'file_name'},
        from_storage => delete $args{'from_storage'},
    );
    open $args{'file_handle'}, ">:raw", $file
        or return ( 0, "Couldn't open '$file' for write: $!" );

    return $self->SUPER::test_args(%args);
}

sub file_name    { return $_[0]->{'opt'}{'file_name'} }
sub file_handle { return $_[0]->{'opt'}{'file_handle'} }

sub run {
    my $self = shift;
    return ( 0, 'no handle' ) unless my $fh = $self->{'opt'}{'file_handle'};

    my %args = ( object => undef, @_ );
    my $query = $args{'object'}->_as_insert_query;
    $query .= "\n" unless $query =~ /\n$/;

    return print $fh $query or return ( 0, "Couldn't write to filehandle" );
    return 1;
}

1;
