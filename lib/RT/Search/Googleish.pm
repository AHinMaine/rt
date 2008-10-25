
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

  RT::Search::Googlish

=head1 SYNOPSIS

=head1 description

Use the argument passed in as a "Google-style" set of keywords

=head1 METHODS




=cut

package RT::Search::Googleish;

use strict;
use base qw(RT::Search);

# sub _init {{{
sub _init {
    my $self = shift;
    my %args = @_;

    $self->{'Queues'} = delete( $args{'Queues'} ) || [];
    $self->SUPER::_init(%args);
}


sub describe {
    my $self = shift;
    return ( _( "No description for %1", ref $self ) );
}


sub query_to_sql {
    my $self     = shift;
    my $query    = shift || $self->argument;
    my @keywords = split /\s+/, $query;
    my ( @tql_clauses, @owner_clauses, @queue_clauses, @user_clauses, @id_clauses, @status_clauses );
    my ( $Queue, $User );
    for my $key (@keywords) {

        # Is this a ticket number? If so, go to it.
        if ( $key =~ m/^\d+$/ ) {
            push @id_clauses, "id = '$key'";
        }

        elsif ( $key =~ /^fulltext:(.*?)$/i ) {
            $key = $1;
            $key =~ s/['\\].*//g;
            push @tql_clauses, "Content LIKE '$key'";

        }

        elsif ( $key =~ /\w+\@\w+/ ) {
            push @user_clauses, "Requestor LIKE '$key'";
        }

        # Is there a status with this name?
        elsif ( $Queue = RT::Model::Queue->new( current_user => $self->tickets_obj->current_user )
            and $Queue->status_schema->is_valid($key) )
        {
            push @status_clauses, "Status = '" . $key . "'";
        }

        # Is there a queue named $key?
        elsif ( $Queue = RT::Model::Queue->new( current_user => $self->tickets_obj->current_user )
            and $Queue->load($key) )
        {
            my $quoted_queue = $Queue->name;
            $quoted_queue =~ s/'/\\'/g;
            push @queue_clauses, "Queue = '$quoted_queue'";
        }

        # Is there a owner named $key?
        elsif ( $User 
                = RT::Model::User->new( current_user => $self->tickets_obj->current_user )
            and $User->load($key)
            and $User->privileged )
        {
            push @owner_clauses, "Owner = '" . $User->name . "'";
        }

        # Else, subject must contain $key
        else {
            $key =~ s/['\\].*//g;
            push @tql_clauses, "subject LIKE '$key'";
        }
    }

    # restrict to any queues requested by the caller
    for my $queue ( @{ $self->{'Queues'} } ) {
        my $queue_obj = RT::Model::Queue->new( current_user => $self->tickets_obj->current_user );
        $queue_obj->load($queue) or next;
        my $quoted_queue = $Queue->name;
        $quoted_queue =~ s/'/\\'/g;
        push @queue_clauses, "Queue = '$quoted_queue'";
    }

    push @tql_clauses, join( " OR ", sort @id_clauses );
    push @tql_clauses, join( " OR ", sort @owner_clauses );
    if ( !@status_clauses ) {
        push @tql_clauses,
          join( " OR ", map "Status = '$_'",
                  RT::Model::Queue->status_schema->active() );
    }
    else {
        push @tql_clauses, join( " OR ", sort @status_clauses );
    }
    push @tql_clauses, join( " OR ", sort @user_clauses );
    push @tql_clauses, join( " OR ", sort @queue_clauses );
    @tql_clauses = grep { $_ ? $_ = "( $_ )" : undef } @tql_clauses;
    return join " AND ", sort @tql_clauses;
}


sub prepare {
    my $self = shift;
    my $tql  = $self->query_to_sql( $self->argument );

    Jifty->log->fatal($tql);

    $self->tickets_obj->from_sql($tql);
    return (1);
}


1;
