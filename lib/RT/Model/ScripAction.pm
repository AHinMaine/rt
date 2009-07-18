use warnings;
use strict;

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

=head1 NAME

  RT::Model::ScripAction - RT Action object

=head1 SYNOPSIS

  use RT::Model::ScripAction;


=head1 description

This module should never be called directly by client code. it's an internal module which
should only be accessed through exported APIs in other modules.



=head1 METHODS

=cut

package RT::Model::ScripAction;
use RT::Model::Template;
use base qw/RT::Record/;

sub table {'ScripActions'}
use Jifty::DBI::Schema;
use Jifty::DBI::Record schema {
    column name            => type is 'text';
    column description     => type is 'text';
    column exec_module     => type is 'text';
    column argument        => type is 'text';
};
use Jifty::Plugin::ActorMetadata::Mixin::Model::ActorMetadata map => {
    created_by => 'creator',
    created_on => 'created',
    updated_by => 'last_updated_by',
    updated_on => 'last_updated'
};


=head2 create

Takes a hash. Creates a new Action entry.  should be better
documented.

=cut

sub delete {
    my $self = shift;

    return ( 0, "ScripAction->delete not implemented" );
}

=head2 load IDENTIFIER

Loads an action by its name.

Returns: id, Error Message

=cut

sub load {
    my $self       = shift;
    my $identifier = shift;

    if ( !$identifier ) {
        return ( 0, _('Input error') );
    }

    if ( $identifier !~ /\D/ ) {
        $self->SUPER::load($identifier);
    } else {
        $self->load_by_cols( 'name', $identifier );

    }

    if (@_) {

        # Set the template id to the passed in template
        my $template = shift;

        $self->{'template'} = $template;
    }
    return ( $self->id, ( _( '%1 ScripAction loaded', $self->id ) ) );
}

=head2 load_action HASH

  Takes a hash consisting of ticket_obj and transaction_obj.  Loads an RT::ScripAction:: module.

=cut

sub load_action {
    my $self = shift;
    my %args = (
        transaction_obj => undef,
        ticket_obj      => undef,
        @_
    );

    $self->{_ticket_obj} = $args{ticket_obj};
    my $type = "RT::ScripAction::" . $self->exec_module;
    Jifty::Util->require($type);

    $self->{'action'} = $type->new(
        argument         => $self->argument,
        current_user     => $self->current_user,
        scrip_obj        => $args{'scrip_obj'},
        template_obj     => $self->template_obj,
        ticket_obj       => $args{'ticket_obj'},
        transaction_obj  => $args{'transaction_obj'},
    );
}

=head2 template_obj

Return this action's template object

TODO: Why are we not using the Scrip's template object?


=cut

sub template_obj {
    my $self = shift;
    return undef unless $self->{template};
    if ( !$self->{'template_obj'} ) {
        $self->{'template_obj'} = RT::Model::Template->new( current_user => $self->current_user );
        $self->{'template_obj'}->load_by_id( $self->{'template'} );

        if ( ( $self->{'template_obj'}->__value('queue') == 0 )
            && $self->{'_ticket_obj'} )
        {
            my $tmptemplate = RT::Model::Template->new( current_user => $self->current_user );
            my ( $ok, $err ) = $tmptemplate->load_queue_template(
                queue => $self->{'_ticket_obj'}->queue->id,
                name  => $self->{'template_obj'}->name
            );

            if ( $tmptemplate->id ) {

                # found the queue-specific template with the same name
                $self->{'template_obj'} = $tmptemplate;
            }
        }

    }

    return ( $self->{'template_obj'} );
}

# The following methods call the action object

sub prepare {
    my $self = shift;
    return ( $self->action->prepare() );

}

sub commit {
    my $self = shift;
    return ( $self->action->commit() );

}

sub describe {
    my $self = shift;
    return ( $self->action->describe() );

}

=head2 action

Return the actual RT::ScripAction object for this scrip.

=cut

sub action {
    my $self = shift;
    return ( $self->{'action'} );
}

sub DESTROY {
    my $self = shift;
    $self->{'_ticket_obj'}  = undef;
    $self->{'action'}       = undef;
    $self->{'template_obj'} = undef;
}

1;

