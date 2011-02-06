# BEGIN BPS TAGGED BLOCK {{{
#
# COPYRIGHT:
#
# This software is Copyright (c) 1996-2010 Best Practical Solutions, LLC
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

package RT::Util;
use strict;
use warnings;


use base 'Exporter';
our @EXPORT_OK = qw/safe_run_child eval_require/;

sub safe_run_child (&) {
    my $our_pid = $$;

    # situation here is wierd, running external app
    # involves fork+exec. At some point after fork,
    # but before exec (or during) code can die in a
    # child. Local is no help here as die throws
    # error out of scope and locals are reset to old
    # values. Instead we set values, eval code, check pid
    # on failure and reset values only in our original
    # process
    my $dbh = $RT::Handle->dbh;
    $dbh->{'InactiveDestroy'} = 1 if $dbh;
    $RT::Handle->{'DisconnectHandleOnDestroy'} = 0;

    my @res;
    my $want = wantarray;
    eval {
        my $code = shift;
        local @ENV{ 'LANG', 'LC_ALL' } = ( 'C', 'C' );
        unless ( defined $want ) {
            $code->();
        } elsif ( $want ) {
            @res = $code->();
        } else {
            @res = ( scalar $code->() );
        }
        1;
    } or do {
        my $err = $@;
        if ( $our_pid == $$ ) {
            $RT::Logger->error( $err );
            $dbh->{'InactiveDestroy'} = 0 if $dbh;
            $RT::Handle->{'DisconnectHandleOnDestroy'} = 1;
        }
        $err =~ s/^Stack:.*$//ms;
        #TODO we need to localize this
        die 'System Error: ' . $err;
    };
    return $want? (@res) : $res[0];
}

sub eval_require ($;$) {
    my $class = shift;
    my $fatal = shift;

    local $@;
    return 1 if eval "require $class; 1";

    if ( $fatal ) {
        return $fatal->() if ref $fatal eq 'CODE';

        require Carp;
        return Carp::croak($@);
    }

    (my $filename = $class) =~ s{::}{/}g;
    if ( rindex( $@, "Can't locate $filename", 0 ) != 0 ) { # doesn't start with
        require Carp;
        return Carp::carp($@);
    }
    return 0;
}

use RT::Base;
RT::Base->_ImportOverlays();

1;
