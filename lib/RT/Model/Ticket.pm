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

=head1 SYNOPSIS

  use RT::Model::Ticket;
  my $ticket = RT::Model::Ticket->new( current_user => $CurrentUser );
  $ticket->load($ticket_id);

=head1 description

This module lets you manipulate RT\'s ticket object.


=head1 METHODS


=cut

package RT::Model::Ticket;
use base qw/RT::HasRoleGroups RT::Record/;

use RT::Model::Queue;
use RT::Model::User;
use RT::Model::LinkCollection;
use RT::Model::CustomFieldCollection;
use RT::Model::TicketCollection;
use RT::Model::TransactionCollection;
use RT::Reminders;
use RT::URI::fsck_com_rt;
use RT::URI;
use MIME::Entity;

use Scalar::Util qw(blessed);

sub table {'Tickets'}

use Jifty::DBI::Schema;
use Jifty::DBI::Record schema {

    column effective_id =>
        max_length is 11,
        type is 'int',
        default is '0';

    column queue =>
        references RT::Model::Queue;

    column type =>
        max_length is 16,
        type is 'varchar(16)',
        default is '';

    column issue_statement =>
        max_length is 11,
        type is 'int',
        default is '0';

    column resolution =>
        max_length is 11,
        type is 'int',
        default is '0';

    column owner =>
        references RT::Model::User;

    column subject =>
        display_length is 50,
        max_length is 200,
        type is 'varchar(200)',
        default is '';

    column initial_priority =>
        max_length is 11,
        type is 'int',
        default is '0';

    column final_priority =>
        max_length is 11,
        type is 'int',
        default is '0';

    column priority      =>
        max_length is 11,
        type is 'int',
        default is '0';

    column time_estimated =>
        max_length is 11,
        type is 'int',
        default is '0',
        label is _( 'time estimated' ),
        hints are _('in minutes');

    column time_worked   =>
        max_length is 11,
        type is 'int',
        default is '0',
        label is _( 'time worked' ),
        hints are _('in minutes');

    column time_left     =>
        max_length is 11,
        type is 'int',
        default is '0',
        label is _('time left'),
        hints are _('in minutes');

    column status        =>
        max_length is 10,
        type is 'varchar(10)',
        default is '',
        render_as 'Select';

    column told          =>
        type is 'timestamp',
        filters are qw( Jifty::Filter::DateTime Jifty::DBI::Filter::DateTime),
        render_as 'DateTime',
        label is _('Last Contact');

    column starts        =>
        type is 'timestamp',
        filters are qw( Jifty::Filter::DateTime Jifty::DBI::Filter::DateTime),
        render_as 'DateTime',
        label is _('Starts');

    column started       =>
        type is 'timestamp',
        filters are qw( Jifty::Filter::DateTime Jifty::DBI::Filter::DateTime),
        render_as 'DateTime',
        label is _('Started');

    column due           =>
        type is 'timestamp',
        filters are qw( Jifty::Filter::DateTime Jifty::DBI::Filter::DateTime),
        render_as 'DateTime',
        label is _('Due');

    column resolved      =>
        type is 'timestamp',
        filters are qw( Jifty::Filter::DateTime Jifty::DBI::Filter::DateTime),
        render_as 'DateTime',
        label is _('Resolved');

    column disabled      =>
        max_length is 6,
        type is 'smallint',
        default is '0';
};

use Jifty::Plugin::ActorMetadata::Mixin::Model::ActorMetadata map => {
    created_by => 'creator',
    created_on => 'created',
    updated_by => 'last_updated_by',
    updated_on => 'last_updated'
};


# A helper table for links mapping to make it easier
# to build and parse links between tickets

our %LINKTYPEMAP = (
    member_of => {
        type => 'member_of',
        mode => 'target',
    },
    parents => {
        type => 'member_of',
        mode => 'target',
    },
    members => {
        type => 'member_of',
        mode => 'base',
    },
    children => {
        type => 'member_of',
        mode => 'base',
    },
    has_member => {
        type => 'member_of',
        mode => 'base',
    },
    refers_to => {
        type => 'refers_to',
        mode => 'target',
    },
    referred_to_by => {
        type => 'refers_to',
        mode => 'base',
    },
    depends_on => {
        type => 'depends_on',
        mode => 'target',
    },
    depended_on_by => {
        type => 'depends_on',
        mode => 'base',
    },
    merged_into => {
        type => 'merged_into',
        mode => 'target',
    },

);


# A helper table for links mapping to make it easier
# to build and parse links between tickets

our %LINKDIRMAP = (
    member_of => {
        base   => 'member_of',
        target => 'has_member',
    },
    refers_to => {
        base   => 'refers_to',
        target => 'referred_to_by',
    },
    depends_on => {
        base   => 'depends_on',
        target => 'depended_on_by',
    },
    merged_into => {
        base   => 'merged_into',
        target => 'merged_into',
    },

);


sub LINKTYPEMAP { return \%LINKTYPEMAP }
sub LINKDIRMAP  { return \%LINKDIRMAP }


=head2 load

Takes a single argument. This can be a ticket id, ticket alias or 
local ticket uri.  If the ticket can't be loaded, returns undef.
Otherwise, returns the ticket id.

=cut

sub load {
    my $self = shift;
    my $id = shift || '';

    #TODO modify this routine to look at effective_id and do the recursive load
    # thing. be careful to cache all the interim tickets we try so we don't loop forever.

    # FIXME: there is no ticket_base_uri option in config
    my $base_uri = RT->config->get('ticket_base_uri') || '';

    #If it's a local URI, turn it into a ticket id
    if ( $base_uri && $id =~ /^$base_uri(\d+)$/ ) {
        $id = $1;
    }

    #If it's a remote URI, we're going to punt for now
    elsif ( $id =~ '://' ) {
        return (undef);
    }

    #If we have an integer URI, load the ticket
    if ( defined $id && $id =~ /^\d+$/ ) {
        my ( $ticketid, $msg ) = $self->load_by_id($id);

        unless ( $self->id ) {
            Jifty->log->debug("$self tried to load a bogus ticket: $id");
            return (undef);
        }
    }

    #It's not a URI. It's not a numerical ticket ID. Punt!
    else {
        Jifty->log->debug("Tried to load a bogus ticket id: '$id'");
        return (undef);
    }

    #If we're merged, resolve the merge.
    if ( ( $self->effective_id ) and ( $self->effective_id != $self->id ) ) {
        Jifty->log->debug( "We found a merged ticket." . $self->id . "/" . $self->effective_id );
        return ( $self->load( $self->effective_id ) );
    }

    #Ok. we're loaded. lets get outa here.
    return ( $self->id );

}




=head2 create (ARGS)

Arguments: ARGS is a hash of named parameters.  Valid parameters are:

  id 
  queue  - Either a queue object or a queue name
  requestor -  A reference to a list of  email addresses or RT user names
  cc  - A reference to a list of  email addresses or names
  admin_cc  - A reference to a  list of  email addresses or names
  type -- The ticket\'s type. ignore this for now
  owner -- This ticket\'s owner. either an RT::Model::User object or this user\'s id
  subject -- A string describing the subject of the ticket
  priority -- an integer from 0 to 99
  initial_priority -- an integer from 0 to 99
  final_priority -- an integer from 0 to 99
  status -- any valid status (Defined in RT::Model::Queue)
  time_estimated -- an integer. estimated time for this task in minutes
  time_worked -- an integer. time worked so far in minutes
  time_left -- an integer. time remaining in minutes
  starts -- an ISO date describing the ticket\'s start date and time in GMT
  due -- an ISO date describing the ticket\'s due date and time in GMT
  mime_obj -- a MIME::Entity object with the content of the initial ticket request.
  cf_<n> -- a scalar or array of values for the customfield with the id <n>

Ticket links can be set up during create by passing the link type as a hask key and
the ticket id to be linked to as a value (or a URI when linking to other objects).
Multiple links of the same type can be created by passing an array ref. For example:

  Parent => 45,
  depends_on => [ 15, 22 ],
  refers_to => 'http://www.bestpractical.com',

Supported link types are C<member_of>, C<has_member>, C<refers_to>, C<referred_to_by>,
C<depends_on> and C<depended_on_by>. Also, C<parents> is alias for C<member_of> and
C<members> and C<children> are aliases for C<has_member>.

Returns: TICKETID, Transaction object, Error Message


=cut

sub create {
    my $self = shift;

    my %args = (
        id                  => undef,
        effective_id        => undef,
        queue               => undef,
        requestor           => undef,
        cc                  => undef,
        admin_cc            => undef,
        type                => 'ticket',
        owner               => undef,
        subject             => '',
        initial_priority    => undef,
        final_priority      => undef,
        priority            => undef,
        status              => 'new',
        time_worked         => "0",
        time_left           => 0,
        time_estimated      => 0,
        due                 => undef,
        starts              => undef,
        started             => undef,
        resolved            => undef,
        told                => undef,
        mime_obj            => undef,
        sign                => 0,
        encrypt             => 0,
        _record_transaction => 1,
        dry_run             => 0,
        @_
    );

    my ( $ErrStr, @non_fatal_errors );

    my $queue_obj = RT::Model::Queue->new( current_user => RT->system_user );
    if ( ref $args{'queue'} && $args{'queue'}->isa('RT::Model::Queue') ) {
        $queue_obj->load( $args{'queue'}->id );
    } elsif ( $args{'queue'} ) {
        $queue_obj->load( $args{'queue'} );
    } else {
        Jifty->log->debug( $args{'queue'} . " not a recognised queue object." );
    }

    #Can't create a ticket without a queue.
    unless ( $queue_obj->id ) {
        Jifty->log->debug("$self No valid queue given for ticket creation.");
        return ( 0, 0, _('Could not create ticket. queue not set') );
    }

    #Now that we have a queue, Check the ACLS
    die caller unless $self->current_user->id;

    #Since we have a queue, we can set queue defaults

    # XXX we should become consistent about requestor vs requestors
    $args{'requestor'} = delete $args{'requestors'}
        unless $args{'requestor'};

# Initial message {{{
    if (!$args{mime_obj}) {
        my $sigless = RT::Interface::Web::strip_content(
            content         => $args{'content'},
            content_type    => $args{'content_type'},
            strip_signature => 1,
            current_user    => $self->current_user,
        );

        # XXX: move make_mime_entity somewhere sane
        $args{mime_obj} = HTML::Mason::Commands::make_mime_entity(
            subject => $args{'subject'},
            from    => $args{'from'},
            cc      => $args{'cc'},
            body    => $sigless,
            type    => $args{'content_type'},
        );
    }
# }}}

    # {{{ Dealing with time fields

    $args{'time_estimated'} = 0 unless defined $args{'time_estimated'};
    $args{'time_worked'}    = 0 unless defined $args{'time_worked'};
    $args{'time_left'}      = 0 unless defined $args{'time_left'};

    # }}}

    # {{{ Deal with setting the owner

    my $owner;
    if ( ref( $args{'owner'} ) && $args{'owner'}->isa('RT::Model::User') ) {
        if ( $args{'owner'}->id ) {
            $owner = $args{'owner'};
        } else {
            Jifty->log->error('passed not loaded owner object');
            push @non_fatal_errors, _("Invalid owner object");
            $owner = undef;
        }
    }

    #If we've been handed something else, try to load the user.
    elsif ( $args{'owner'} ) {
        $owner = RT::Model::User->new;
        $owner->load( $args{'owner'} );
        unless ( $owner->id ) {
            push @non_fatal_errors, _("Owner could not be set.") . " " . _( "User '%1' could not be found.", $args{'owner'} );
            $owner = undef;
        }
    }

    #If we have a proposed owner and they don't have the right
    #to own a ticket, scream about it and make them not the owner

    my $defer_owner;
    if (   $owner
        && $owner->id != RT->nobody->id
        && !$owner->has_right( object => $queue_obj, right => 'OwnTicket' ) )
    {
        $defer_owner = $owner;
        $owner       = undef;
        Jifty->log->debug('going to defer setting owner');

    }

    #If we haven't been handed a valid owner, make it nobody.
    unless ( defined($owner) && $owner->id ) {
        $owner = RT::Model::User->new;
        $owner->load( RT->nobody->id );
    }

    # }}}

    # We attempt to load or create each of the people who might have a role for this ticket
    # _outside_ the transaction, so we don't get into ticket creation races
    foreach my $type ( $self->roles ) {

        $args{$type} = [ $args{$type} ] unless ref $args{$type} eq 'ARRAY';
        foreach my $watcher ( grep $_, splice @{ $args{$type} } ) {
            if ( $watcher =~ /^\d+$/ ) {
                push @{ $args{$type} }, $watcher;
            } else {
                my @addresses = RT::EmailParser->parse_email_address($watcher);
                foreach my $address (@addresses) {
                    my $user = RT::Model::User->new( current_user => RT->system_user );
                    my ( $uid, $msg ) = $user->load_or_create_by_email($address);
                    unless ($uid) {
                        push @non_fatal_errors, _( "Couldn't load or create user: %1", $msg );
                    } else {
                        push @{ $args{$type} }, $user->id;
                    }
                }
            }
        }
    }

    Jifty->handle->begin_transaction();

    my %params = (
        queue            => $queue_obj->id,
        owner            => $owner->id,
        subject          => $args{'subject'},
        initial_priority => $args{'initial_priority'},
        final_priority   => $args{'final_priority'},
        priority         => $args{'priority'},
        status           => $args{'status'},
        time_worked      => $args{'time_worked'},
        time_estimated   => $args{'time_estimated'},
        time_left        => $args{'time_left'},
        type             => $args{'type'},
        starts           => $args{'starts'},
        started          => $args{'started'},
        resolved         => $args{'resolved'},
        told             => $args{'told'},
        due              => $args{'due'},
    );

    # Parameters passed in during an import that we probably don't want to touch, otherwise
    foreach my $attr qw(id creator created last_updated last_updated_by) {
        $params{$attr} = $args{$attr} if $args{$attr};
    }

    # Delete null integer parameters
    foreach my $attr qw(time_worked time_left time_estimated initial_priority final_priority) {
        delete $params{$attr}
            unless ( exists $params{$attr} && $params{$attr} );
    }

    # Delete the time worked if we're counting it in the transaction
    delete $params{'time_worked'} if $args{'_record_transaction'};

    my ( $id, $ticket_message ) = $self->SUPER::create(%params);
    unless ($id) {
        Jifty->log->fatal( "Couldn't create a ticket: " . $ticket_message );
        Jifty->handle->rollback();
        return ( 0, 0, _("Ticket could not be created due to an internal error") );
    }

    #Set the ticket's effective ID now that we've created it.
    my ( $val, $msg ) = $self->__set(
        column => 'effective_id',
        value  => ( $args{'effective_id'} || $id )
    );
    unless ($val) {
        Jifty->log->fatal("Couldn't set effective_id: $msg");
        Jifty->handle->rollback;
        return ( 0, 0, _("Ticket could not be created due to an internal error") );
    }

    ((my $owner_group), $msg) = $self->create_role('owner');
    unless ( $owner_group ) {
        Jifty->log->fatal( "Aborting ticket creation because of above error." );
        Jifty->handle->rollback();
        return ( 0, 0, _("Ticket could not be created due to an internal error") );
    }

    # Set the owner in the Groups table
    # We denormalize it into the Ticket table too because doing otherwise would
    # kill performance, bigtime. It gets kept in lockstep thanks to the magic of transactionalization
    ( $val, $msg ) = $owner_group->_add_member(
        principal => $owner,
    ) unless $defer_owner;

    # {{{ Deal with setting up watchers

    foreach my $type ( $self->roles ) {

        # we know it's an array ref
        foreach my $watcher ( @{ $args{$type} } ) {

            # Note that we're using add_watcher, rather than _add_watcher, as we
            # actually _want_ that ACL check. Otherwise, random ticket creators
            # could make themselves adminccs and maybe get ticket rights. that would
            # be poor
            my $method = $type eq 'admin_cc' ? 'add_watcher' : '_add_watcher';

            my ( $val, $msg ) = $self->$method(
                type         => $type,
                principal => $watcher,
                silent       => 1,
            );
            push @non_fatal_errors, _( "Couldn't set %1 watcher: %2", $type, $msg )
                unless $val;
        }
    }

    # }}}

    # {{{ Add all the custom fields

    foreach my $arg ( keys %args ) {
        next unless $arg =~ /^cf_(\d+)$/i;
        my $cfid = $1;

        foreach my $value (
            UNIVERSAL::isa( $args{$arg} => 'ARRAY' )
            ? @{ $args{$arg} }
            : ( $args{$arg} )
            )
        {
            next unless defined $value && length $value;

            # Allow passing in uploaded large_content etc by hash reference
            my ( $status, $msg ) = $self->add_custom_field_value(
                (   UNIVERSAL::isa( $value => 'HASH' )
                    ? %$value
                    : ( value => $value )
                ),
                field              => $cfid,
                record_transaction => 0,
            );
            push @non_fatal_errors, $msg unless $status;
        }
    }

    # }}}

    # {{{ Deal with setting up links

    # TODO: Adding link may fire scrips on other end and those scrips
    # could create transactions on this ticket before 'create' transaction.
    #
    # We should implement different schema: record 'create' transaction,
    # create links and only then fire create transaction's scrips.
    #
    # Ideal variant: add all links without firing scrips, record create
    # transaction and only then fire scrips on the other ends of links.
    #
    # //RUZ

    foreach my $type ( keys %LINKTYPEMAP ) {
        next unless $args{$type};
        foreach my $link ( ref( $args{$type} ) ? @{ $args{$type} } : ( $args{$type} ) ) {

            # Check rights on the other end of the link if we must
            # then run _add_link that doesn't check for ACLs
            if ( RT->config->get('strict_link_acl') ) {
                my ( $val, $msg, $obj ) = $self->_get_ticket_from_uri( URI => $link );
                unless ($val) {
                    push @non_fatal_errors, $msg;
                    next;
                }

                if ( $obj && !$obj->current_user_has_right('ModifyTicket') ) {
                    push @non_fatal_errors, _('Linking. Permission denied');
                    next;
                }
            }

            my ( $wval, $wmsg ) = $self->_add_link(
                type                          => $LINKTYPEMAP{$type}->{'type'},
                $LINKTYPEMAP{$type}->{'mode'} => $link,
                silent                        => !$args{'_record_transaction'},
                'silent_' . ( $LINKTYPEMAP{$type}->{'mode'} eq 'base' ? 'target' : 'base' ) => 1,
            );

            push @non_fatal_errors, $wmsg unless ($wval);
        }
    }

    # }}}
    # Now that we've created the ticket and set up its metadata, we can actually go and check OwnTicket on the ticket itself.
    # This might be different than before in cases where extensions like RTIR are doing clever things with RT's ACL system
    if ($defer_owner) {
        if ( !$defer_owner->has_right( object => $self, right => 'OwnTicket' ) ) {

            Jifty->log->warn( "User "
                  . $defer_owner->name . "("
                  . $defer_owner->id
                  . ") was proposed as a ticket owner but has no rights to own "
                  . "tickets in "
                  . $queue_obj->name );
            push @non_fatal_errors,
              _( "Owner '%1' does not have rights to own this ticket.",
                $defer_owner->name );

        } else {
            $owner = $defer_owner;
            $self->__set( column => 'owner', value => $owner->id );

        }
        $owner_group->_add_member(
            principal => $owner,
        );
    }

    foreach my $argument (qw(encrypt sign)) {
        my $header = "X-RT-" . ucfirst($argument);
        $args{'mime_obj'}->head->add( $header => $args{$argument} )
            if defined $args{$argument};
    }

    if ($args{'attachments'}) {
        # Once multi-upload works we probably won't have to do this coercion
        $args{'attachments'} = [$args{'attachments'}]
            if ref($args{'attachments'}) ne 'ARRAY';

        for my $attachment (@{ $args{'attachments'} }) {
            $args{'mime_obj'}->attach(
                Data     => $attachment->content,
                Type     => $attachment->content_type,
                Filename => $attachment->filename,
            );
        }
    }

    if ( $args{'_record_transaction'} ) {

        # {{{ Add a transaction for the create
        my ( $Trans, $Msg, $TransObj ) = $self->_new_transaction(
            type          => "create",
            time_taken    => $args{'time_worked'},
            mime_obj      => $args{'mime_obj'},
            commit_scrips => !$args{'dry_run'},
        );
        if ( $self->id && $Trans ) {

            $TransObj->update_custom_fields(%args);

            Jifty->log->info( "Ticket " . $self->id . " created in queue '" . $queue_obj->name . "' by " . $self->current_user->name );
            $ErrStr = _( "Ticket %1 created in queue '%2'", $self->id, $queue_obj->name );
            $ErrStr = join( "\n", $ErrStr, @non_fatal_errors );
        } else {
            Jifty->handle->rollback();

            $ErrStr = join( "\n", $ErrStr, @non_fatal_errors );
            Jifty->log->error("Ticket couldn't be created: $ErrStr");
            return ( 0, 0, _("Ticket could not be created due to an internal error") );
        }
        if ( $args{'dry_run'} ) {
            Jifty->handle->rollback();
            return ( $self->id, $TransObj, $ErrStr );
        }

        Jifty->handle->commit();
        return ( $self->id, $TransObj->id, $ErrStr );

        # }}}
    } else {

        # Not going to record a transaction
        Jifty->handle->commit();
        $ErrStr = _( "Ticket %1 created in queue '%2'", $self->id, $queue_obj->name );
        $ErrStr = join( "\n", $ErrStr, @non_fatal_errors );
        return ( $self->id, 0, $ErrStr );

    }
}


=head2 canonicalize_due

Try to parse the due date as a string, falling back to the queue's
default-due-in (but only if canonicalizing a due date for ticket creation)

=cut

sub canonicalize_due {
    my $self     = shift;
    my $due      = shift;
    my $other    = shift;
    my $metadata = shift;

    if ( defined $due ) {
        return RT::DateTime->new_from_string($due);
    }

    if ($metadata->{for} eq 'create') {
        my $queue_obj = RT::Model::Queue->load($self->queue_id || $other->{queue});

        if ( my $due_in = $queue_obj->default_due_in ) {
            my $due = RT::DateTime->now;
            return $due->add(days => $due_in);
        }
    }

    return RT::DateTime->new_unset;
}

=head2 canonicalize_starts

Try to parse the starts date as a string.

=cut

sub canonicalize_starts {
    my $self   = shift;
    my $starts = shift;

    if (defined $starts) {
        return RT::DateTime->new_from_string($starts);
    }

    return RT::DateTime->new_unset;
}

=head2 canonicalize_started

Try to parse the started date as a string. If the status is not one of the
queue's initial statuses, then a default of "now" will be used.

=cut

sub canonicalize_started {
    my $self    = shift;
    my $started = shift;
    my $other   = shift;

    if (defined $started) {
        return RT::DateTime->new_from_string($started);
    }

    my $queue_obj = RT::Model::Queue->load($self->queue_id || $other->{queue});

    if ( !$queue_obj->status_schema->is_initial($other->{status}) ) {
        return RT::DateTime->now;
    }

    return RT::DateTime->new_unset;
}

=head2 canonicalize_resolved

Try to parse the resolved date as a string. If the status is inactive, then a
default of "now" will be used.

=cut

sub canonicalize_resolved {
    my $self     = shift;
    my $resolved = shift;
    my $other    = shift;

    if (defined $resolved) {
        return RT::DateTime->new_from_string($resolved);
    }

    my $queue_obj = RT::Model::Queue->load($self->queue_id || $other->{queue});

    if ($queue_obj->status_schema->is_inactive($other->{status})) {
        return RT::DateTime->now;
    }

    return RT::DateTime->new_unset;
}

=head2 canonicalize_told

Try to parse the told date as a string.

=cut

sub canonicalize_told {
    my $self = shift;
    my $told = shift;

    if (defined $told) {
        return RT::DateTime->new_from_string($told);
    }

    return RT::DateTime->new_unset;
}

sub _canonicalize_priority {
    my $self   = shift;
    my $method = shift;
    my $value  = shift;
    my $other  = shift;

    return $value if defined $value;

    my $queue_obj = RT::Model::Queue->load($self->queue_id || $other->{queue});

    return $queue_obj->$method || 0;
}

=head2 canonicalize_initial_priority

Fallback to the queue's initial priority if available, or 0.

=cut

sub canonicalize_initial_priority {
    my $self = shift;
    $self->_canonicalize_priority('initial_priority', @_);
}

=head2 canonicalize_final_priority

Fallback to the queue's final priority if available, or 0.

=cut

sub canonicalize_final_priority {
    my $self = shift;
    $self->_canonicalize_priority('final_priority', @_);
}

=head2 canonicalize_priority

Fallback to the initial priority.

=cut

sub canonicalize_priority {
    my $self     = shift;
    my $priority = shift;
    my $other    = shift;

    return $priority if defined $priority;

    # Otherwise, we should canonicalize to initial_priority. But
    # canonicalizations are unordered, so we need to play a little dirty
    my $initial = $self->canonicalize_initial_priority($other->{initial_priority}, $other, @_);

    return $initial;
}

sub roles { return ( "cc", "admin_cc", "requestor" ); }

=head2 squelch_mail_to [EMAIL]

Takes an optional email address to never email about updates to this ticket.


Returns an array of the RT::Model::Attribute objects for this ticket's 'SquelchMailTo' attributes.


=cut

sub squelch_mail_to {
    my $self = shift;
    if (@_) {
        unless ( $self->current_user_has_right('ModifyTicket') ) {
            return undef;
        }
        my $attr = shift;
        $self->add_attribute( name => 'SquelchMailTo', content => $attr )
            unless grep { $_->content eq $attr } $self->attributes->named('SquelchMailTo');

    }
    unless ( $self->current_user_has_right('ShowTicket') ) {
        return undef;
    }
    my @attributes = $self->attributes->named('SquelchMailTo');
    return (@attributes);
}

=head2 unsquelch_mail_to ADDRESS

Takes an address and removes it from this ticket's "SquelchMailTo" list. If an address appears multiple times, each instance is removed.

Returns a tuple of (status, message)

=cut

sub unsquelch_mail_to {
    my $self = shift;

    my $address = shift;
    unless ( $self->current_user_has_right('ModifyTicket') ) {
        return ( 0, _("Permission Denied") );
    }

    my ( $val, $msg ) = $self->attributes->delete_entry(
        name    => 'SquelchMailTo',
        content => $address
    );
    return ( $val, $msg );
}

=head2 transaction_addresses

Returns a composite hashref of the results of L<RT::Model::Transaction/Addresses> for all this ticket's Create, comment or correspond transactions.
The keys are C<To>, C<cc> and C<Bcc>. The values are lists of C<Email::Address> objects.

NOTE: For performance reasons, this method might want to skip transactions and go straight for attachments. But to make that work right, we're going to need to go and walk around the access control in Attachment.pm's sub _value.

=cut

sub transaction_addresses {
    my $self = shift;
    my $txns = $self->transactions;

    my %addresses = ();
    foreach my $type (qw(Create comment correspond)) {
        $txns->limit(
            column           => 'type',
            operator         => '=',
            value            => $type,
            entry_aggregator => 'OR',
            case_sensitive   => 1
        );
    }

    while ( my $txn = $txns->next ) {
        my $txnaddrs = $txn->addresses;
        foreach my $addrlist ( values %$txnaddrs ) {
            foreach my $addr (@$addrlist) {

                # Skip addresses without a phrase (things that are just raw addresses) if we have a phrase
                next
                    if ( $addresses{ $addr->address }
                    && $addresses{ $addr->address }->phrase
                    && not $addr->phrase );

                # skips "comment-only" addresses
                next unless ( $addr->address );
                $addresses{ $addr->address } = $addr;
            }
        }
    }

    return \%addresses;

}



sub validate_queue {
    my $self  = shift;
    my $value = shift;
    my $other = shift;
    my $meta  = shift;

    if ( !$value ) {
        Jifty->log->warn( " RT::Model::Ticket::validate_queue called with a null value." );
        return (1);
    }

    my $queue_obj = RT::Model::Queue->load($value);

    if ($meta->{for} eq 'create') {
        if ( $queue_obj->disabled ) {
            Jifty->log->debug( "$self Disabled queue '"
                . $queue_obj->name
                . "' given for ticket creation." );
            return (
                0,
                _(
                    'Could not create ticket in disabled queue "%1"',
                    $queue_obj->name
                )
            );
        }

        unless (
            $self->current_user->has_right(
                right  => 'CreateTicket',
                object => $queue_obj
            )
            )
        {
            return ( 0, _( "No permission to create tickets in the queue '%1'", $queue_obj->name ) );
        }
    }

    if ($queue_obj->id) {
        return (1);
    } else {
        return (undef);
    }
}



sub set_queue {
    my $self     = shift;
    my $NewQueue = shift;

    #Redundant. ACL gets checked in _set;
    unless ( $self->current_user_has_right('ModifyTicket') ) {
        return ( 0, _("Permission Denied") );
    }

    my $Newqueue_obj = RT::Model::Queue->load($NewQueue);

    unless ( $Newqueue_obj->id() ) {
        return ( 0, _("That queue does not exist") );
    }

    if ( $Newqueue_obj->id == $self->queue->id ) {
        return ( 0, _('That is the same value') );
    }
    unless (
        $self->current_user->has_right(
            right  => 'CreateTicket',
            object => $Newqueue_obj
        )
        )
    {
        return ( 0, _("You may not create requests in that queue.") );
    }

    my $new_status;
    my $schema = $self->queue->status_schema;
    if ( $schema->name ne $Newqueue_obj->status_schema->name ) {
        unless ( $schema->has_map( $Newqueue_obj->status_schema ) ) {
            return ( 0, _("There is no mapping for statuses between these queues. Contact your system administrator.") );
        }
        $new_status = $schema->map( $Newqueue_obj )->{ $self->status };
        return ( 0, _("Mapping between queues' workflows is incomplete. Contact your system administrator.") )
            unless $new_status;
    }

    unless (
        $self->owner->has_right(
            right  => 'OwnTicket',
            object => $Newqueue_obj
        )
        )
    {
        my $clone = RT::Model::Ticket->new( current_user => RT->system_user );
        $clone->load( $self->id );
        unless ( $clone->id ) {
            return ( 0, _( "Couldn't load copy of ticket #%1.", $self->id ) );
        }
        my ( $status, $msg ) = $clone->set_owner( RT->nobody->id, 'Force' );
        Jifty->log->error("Couldn't set owner on queue change: $msg")
            unless $status;
    }

    my ( $status, $msg ) =
      $self->_set( column => 'queue', value => $Newqueue_obj->id() );

    if ($status) {

        # On queue change, change queue for reminders too
        my $reminder_collection = $self->reminders->collection;
        while ( my $reminder = $reminder_collection->next ) {
            my ( $status, $msg ) = $reminder->set_queue($NewQueue);
            Jifty->log->error( 'Queue change failed for reminder #'
                  . $reminder->id . ': '
                  . $msg )
              unless $status;
        }
        if ( $new_status ) {
            my ($status, $msg) = $self->set_status( status => $new_status, force => 1 );
            Jifty->log->error( 'Status change failed on queue change: ' . $msg )
                unless $status;
        }
    }

    return ( $status, $msg );
}



=head2 set_started

Takes a date in ISO format or undef
Returns a transaction id and a message
The client calls "Start" to note that the project was started on the date in $date.
A null date means "now"

=cut

sub set_started {
    my $self = shift;
    my $time = shift || 0;

    unless ( $self->current_user_has_right('ModifyTicket') ) {
        return ( 0, _("Permission Denied") );
    }

    #We create a date object to catch date weirdness
    my $time_obj;
    if ($time) {
        $time_obj = RT::DateTime->new_from_string($time);
    } else {
        $time_obj = RT::DateTime->now;
    }

    #Now that we're starting, open this ticket
    #TODO do we really want to force this as policy? it should be a scrip

    #We need $TicketAsSystem, in case the current user doesn't have
    #ShowTicket
    #
    my $TicketAsSystem = RT::Model::Ticket->new( current_user => RT->system_user );
    $TicketAsSystem->load( $self->id );
    if ( $TicketAsSystem->status eq 'new' ) {
        $TicketAsSystem->set_status('open');
    }

    return ( $self->_set( column => 'started', value => $time_obj->iso ) );

}

=head2 time_worked_as_string

Returns the amount of time worked on this ticket as a Text String

=cut

sub time_worked_as_string {
    my $self = shift;
    return "0" unless $self->time_worked;

    #This is not really a date object, but if we diff a number of seconds
    #vs the epoch, we'll get a nice description of time worked.

    return RT::DateTime::Duration->new(minutes => $self->time_worked)->as_string;
}

=head2 comment

comment on this ticket.
Takes a hashref with the following attributes:
If mime_obj is undefined, content will be used to build a MIME::Entity for this
commentl

mime_obj, time_taken, cc_message_to, bcc_message_to, Content, dry_run

If dry_run is defined, this update WILL NOT BE RECORDED. Scrips will not be committed.
They will, however, be prepared and you'll be able to access them through the transaction_obj

Returns: Transaction id, Error Message, Transaction object
(note the different order from Create()!)

=cut

sub comment {
    my $self = shift;

    my %args = (
        cc_message_to  => undef,
        bcc_message_to => undef,
        mime_obj       => undef,
        content        => undef,
        time_taken     => 0,
        dry_run        => 0,
        @_
    );

    unless ( ( $self->current_user_has_right('CommentOnTicket') )
        or ( $self->current_user_has_right('ModifyTicket') ) )
    {
        return ( 0, _("Permission Denied"), undef );
    }
    $args{'note_type'} = 'comment';

    if ( $args{'dry_run'} ) {
        Jifty->handle->begin_transaction();
        $args{'commit_scrips'} = 0;
    }

    my @results = $self->_record_note(%args);
    if ( $args{'dry_run'} ) {
        Jifty->handle->rollback();
    }

    return (@results);
}


=head2 correspond

Correspond on this ticket.
Takes a hashref with the following attributes:


mime_obj, time_taken, cc_message_to, bcc_message_to, Content, dry_run

if there's no mime_obj, content is used to build a MIME::Entity object

If dry_run is defined, this update WILL NOT BE RECORDED. Scrips will not be committed.
They will, however, be prepared and you'll be able to access them through the transaction_obj

Returns: Transaction id, Error Message, Transaction object
(note the different order from Create()!)


=cut

sub correspond {
    my $self = shift;
    my %args = (
        cc_message_to  => undef,
        bcc_message_to => undef,
        mime_obj       => undef,
        content        => undef,
        time_taken     => 0,
        @_
    );

    unless ( ( $self->current_user_has_right('ReplyToTicket') )
        or ( $self->current_user_has_right('ModifyTicket') ) )
    {
        return ( 0, _("Permission Denied"), undef );
    }

    $args{'note_type'} = 'correspond';
    if ( $args{'dry_run'} ) {
        Jifty->handle->begin_transaction();
        $args{'commit_scrips'} = 0;
    }

    my @results = $self->_record_note(%args);

    #Set the last told date to now if this isn't mail from the requestor.
    #TODO: Note that this will wrongly ack mail from any non-requestor as a "told"
    $self->set_told
      unless $self->is_watcher(
              type         => 'requestor',
              principal => $self->current_user->id,
      );

    if ( $args{'dry_run'} ) {
        Jifty->handle->rollback();
    }

    return (@results);

}



=head2 _record_note

the meat of both comment and correspond. 

Performs no access control checks. hence, dangerous.

=cut

sub _record_note {
    my $self = shift;
    my %args = (
        cc_message_to  => undef,
        bcc_message_to => undef,
        encrypt        => undef,
        sign           => undef,
        mime_obj       => undef,
        content        => undef,
        note_type      => 'correspond',
        time_taken     => 0,
        commit_scrips  => 1,
        @_
    );

    unless ( $args{'mime_obj'} || $args{'content'} ) {
        return ( 0, _("No message attached"), undef );
    }

    unless ( $args{'mime_obj'} ) {
        $args{'mime_obj'} = MIME::Entity->build( Data => ( ref $args{'content'} ? $args{'content'} : [ $args{'content'} ] ) );
    }

    # convert text parts into utf-8
    RT::I18N::set_mime_entity_to_utf8( $args{'mime_obj'} );

    # If we've been passed in cc_message_to and bcc_message_to fields,
    # add them to the mime object for passing on to the transaction handler
    # The "NotifyOtherRecipients" scripAction will look for RT-Send-cc: and
    # RT-Send-Bcc: headers

    foreach my $type (qw/cc bcc/) {
        next unless defined $args{ $type . '_message_to' };

        my $addresses = join ', ', ( map {
                RT::Model::User->canonicalize_email( $_->address ) } Email::Address->parse( $args{ $type . '_message_to' } ) );
        $args{'mime_obj'}->head->add( 'RT-Send-' . $type, $addresses );
    }

    foreach my $argument (qw(encrypt sign)) {
        my $header = "X-RT-" . ucfirst($argument);
        $args{'mime_obj'}->head->add( $header => $args{$argument} )
            if defined $args{$argument};
    }

    # If this is from an external source, we need to come up with its
    # internal Message-ID now, so all emails sent because of this
    # message have a common Message-ID
    my $org   = RT->config->get('organization');
    my $msgid = $args{'mime_obj'}->head->get('Message-ID');
    unless ( defined $msgid
        && $msgid =~ /<(rt-.*?-\d+-\d+)\.(\d+-0-0)\@\Q$org\E>/ )
    {
        $args{'mime_obj'}->head->set( 'RT-Message-ID' => RT::Interface::Email::gen_message_id( Ticket => $self ) );
    }

    #Record the correspondence (write the transaction)
    my ( $Trans, $msg, $TransObj ) = $self->_new_transaction(
        type          => $args{'note_type'},
        data          => ( $args{'mime_obj'}->head->get('subject') || 'No subject' ),
        time_taken    => $args{'time_taken'},
        mime_obj      => $args{'mime_obj'},
        commit_scrips => $args{'commit_scrips'},
    );

    unless ($Trans) {
        Jifty->log->err("$self couldn't init a transaction $msg");
        return ( $Trans, _("Message could not be recorded"), undef );
    }

    return ( $Trans, _("Message recorded"), $TransObj );
}




sub _links {
    my $self = shift;

    #TODO: Field isn't the right thing here. but I ahave no idea what mnemonic ---
    #tobias meant by $f
    my $field = shift;
    my $type = shift || "";

    unless ( $self->{"$field$type"} ) {
        $self->{"$field$type"} = RT::Model::LinkCollection->new;
        if ( $self->current_user_has_right('ShowTicket') ) {

            # Maybe this ticket is a merged ticket
            my $Tickets = RT::Model::TicketCollection->new;

            # at least to myself
            $self->{"$field$type"}->limit(
                column           => $field,
                value            => $self->uri,
                entry_aggregator => 'OR'
            );
            $Tickets->limit(
                column => 'effective_id',
                value  => $self->effective_id
            );
            while ( my $Ticket = $Tickets->next ) {
                $self->{"$field$type"}->limit(
                    column           => $field,
                    value            => $Ticket->uri,
                    entry_aggregator => 'OR'
                );
            }
            $self->{"$field$type"}->limit(
                column => 'type',
                value  => $type
            ) if ($type);
        }
    }
    return ( $self->{"$field$type"} );
}



=head2 delete_link

Delete a link. takes a paramhash of base, target, type, silent,
silent_base and silent_target. Either base or target must be null.
The null value will be replaced with this ticket\'s id.

If silent is true then no transaction would be recorded, in other
case you can control creation of transactions on both base and
target with silent_base and silent_target respectively. By default
both transactions are created.

=cut 

sub delete_link {
    my $self = shift;
    my %args = (
        base          => undef,
        target        => undef,
        type          => undef,
        silent        => undef,
        silent_base   => undef,
        silent_target => undef,
        @_
    );

    unless ( $args{'target'} || $args{'base'} ) {
        Jifty->log->error("base or target must be specified");
        return ( 0, _('Either base or target must be specified') );
    }

    #check acls
    my $right = 0;
    $right++ if $self->current_user_has_right('ModifyTicket');
    if ( !$right && RT->config->get('strict_link_acl') ) {
        return ( 0, _("Permission Denied") );
    }

    # If the other URI is an RT::Model::Ticket, we want to make sure the user
    # can modify it too...
    my ( $status, $msg, $other_ticket )
        = $self->_get_ticket_from_uri( URI => $args{'target'} || $args{'base'} );
    return ( 0, $msg ) unless $status;
    if (  !$other_ticket
        || $other_ticket->current_user_has_right('ModifyTicket') )
    {
        $right++;
    }
    if (   ( !RT->config->get('strict_link_acl') && $right == 0 )
        || ( RT->config->get('strict_link_acl') && $right < 2 ) )
    {
        return ( 0, _("Permission Denied") );
    }

    my ( $val, $Msg ) = $self->SUPER::_delete_link(%args);
    return ( 0, $Msg ) unless $val;

    return ( $val, $Msg ) if $args{'silent'};

    my ( $direction, $remote_link );

    if ( $args{'base'} ) {
        $remote_link = $args{'base'};
        $direction   = 'target';
    } elsif ( $args{'target'} ) {
        $remote_link = $args{'target'};
        $direction   = 'base';
    }

    my $remote_uri = RT::URI->new;
    $remote_uri->from_uri($remote_link);

    unless ( $args{ 'silent_' . $direction } ) {
        my ( $Trans, $Msg, $TransObj ) = $self->_new_transaction(
            type       => 'delete_link',
            field      => $LINKDIRMAP{ $args{'type'} }->{$direction},
            old_value  => $remote_uri->uri || $remote_link,
            time_taken => 0
        );
        Jifty->log->error("Couldn't create transaction: $Msg") unless $Trans;
    }

    if (  !$args{ 'silent_' . ( $direction eq 'target' ? 'base' : 'target' ) }
        && $remote_uri->is_local )
    {
        my $OtherObj = $remote_uri->object;
        my ( $val, $Msg ) = $OtherObj->_new_transaction(
            type  => 'delete_link',
            field => $direction eq 'target'
            ? $LINKDIRMAP{ $args{'type'} }->{base}
            : $LINKDIRMAP{ $args{'type'} }->{target},
            old_value       => $self->uri,
            activate_scrips => !RT->config->get('link_transactions_run1_scrip'),
            time_taken      => 0,
        );
        Jifty->log->error("Couldn't create transaction: $Msg") unless $val;
    }

    return ( $val, $Msg );
}



=head2 add_link

Takes a paramhash of type and one of base or target. Adds that link to this ticket.

If silent is true then no transaction would be recorded, in other
case you can control creation of transactions on both base and
target with silent_base and silent_target respectively. By default
both transactions are created.

=cut

sub add_link {
    my $self = shift;
    my %args = (
        target        => '',
        base          => '',
        type          => '',
        silent        => undef,
        silent_base   => undef,
        silent_target => undef,
        @_
    );

    unless ( $args{'target'} || $args{'base'} ) {
        Jifty->log->error("base or target must be specified");
        return ( 0, _('Either base or target must be specified') );
    }

    my $right = 0;
    $right++ if $self->current_user_has_right('ModifyTicket');
    if ( !$right && RT->config->get('strict_link_acl') ) {
        return ( 0, _("Permission Denied") );
    }

    # If the other URI is an RT::Model::Ticket, we want to make sure the user
    # can modify it too...
    my ( $status, $msg, $other_ticket )
        = $self->_get_ticket_from_uri( URI => $args{'target'} || $args{'base'} );
    return ( 0, $msg ) unless $status;
    if (  !$other_ticket
        || $other_ticket->current_user_has_right('ModifyTicket') )
    {
        $right++;
    }
    if (   ( !RT->config->get('strict_link_acl') && $right == 0 )
        || ( RT->config->get('strict_link_acl') && $right < 2 ) )
    {
        return ( 0, _("Permission Denied") );
    }

    return $self->_add_link(%args);
}

sub _get_ticket_from_uri {
    my $self = shift;
    my %args = ( URI => '', @_ );

    # If the other URI is an RT::Model::Ticket, we want to make sure the user
    # can modify it too...
    my $uri_obj = RT::URI->new;
    $uri_obj->from_uri( $args{'URI'} );

    unless ( $uri_obj->resolver && $uri_obj->scheme ) {
        my $msg = _( "Couldn't resolve '%1' into a URI.", $args{'URI'} );
        Jifty->log->warn($msg);
        return ( 0, $msg );
    }
    my $obj = $uri_obj->resolver->object;
    unless ( UNIVERSAL::isa( $obj, 'RT::Model::Ticket' ) && $obj->id ) {
        return ( 1, 'Found not a ticket', undef );
    }
    return ( 1, 'Found ticket', $obj );
}

=head2 _add_link  

Private non-acled variant of add_link so that links can be added during create.

=cut

sub _add_link {
    my $self = shift;
    my %args = (
        target        => '',
        base          => '',
        type          => '',
        silent        => undef,
        silent_base   => undef,
        silent_target => undef,
        @_
    );

    my ( $val, $msg, $exist ) = $self->SUPER::_add_link(%args);
    return ( $val, $msg ) if !$val || $exist;
    return ( $val, $msg ) if $args{'silent'};

    my ( $direction, $remote_link );
    if ( $args{'target'} ) {
        $remote_link = $args{'target'};
        $direction   = 'base';
    } elsif ( $args{'base'} ) {
        $remote_link = $args{'base'};
        $direction   = 'target';
    }

    my $remote_uri = RT::URI->new;
    $remote_uri->from_uri($remote_link);

    unless ( $args{ 'silent_' . $direction } ) {
        my ( $Trans, $Msg, $TransObj ) = $self->_new_transaction(
            type       => 'add_link',
            field      => $LINKDIRMAP{ $args{'type'} }->{$direction},
            new_value  => $remote_uri->uri || $remote_link,
            time_taken => 0
        );
        Jifty->log->error("Couldn't create transaction: $Msg") unless $Trans;
    }

    if (  !$args{ 'silent_' . ( $direction eq 'target' ? 'base' : 'target' ) }
        && $remote_uri->is_local )
    {
        my $OtherObj = $remote_uri->object;
        my ( $val, $msg ) = $OtherObj->_new_transaction(
            type  => 'add_link',
            field => $direction eq 'target'
            ? $LINKDIRMAP{ $args{'type'} }->{base}
            : $LINKDIRMAP{ $args{'type'} }->{target},
            new_value       => $self->uri,
            activate_scrips => !RT->config->get('link_transactions_run1_scrip'),
            time_taken      => 0,
        );
        Jifty->log->error("Couldn't create transaction: $msg") unless $val;
    }

    return ( $val, $msg );
}



=head2 merge_into

merge_into take the id of the ticket to merge this ticket into.



=cut

sub merge_into {
    my $self      = shift;
    my $ticket_id = shift;

    unless ( $self->current_user_has_right('ModifyTicket') ) {
        return ( 0, _("Permission Denied") );
    }

    # Load up the new ticket.
    my $MergeInto = RT::Model::Ticket->new( current_user => RT->system_user );
    $MergeInto->load($ticket_id);

    # make sure it exists.
    unless ( $MergeInto->id ) {
        return ( 0, _("New ticket doesn't exist") );
    }

    # Make sure the current user can modify the new ticket.
    unless ( $MergeInto->current_user_has_right('ModifyTicket') ) {
        return ( 0, _("Permission Denied") );
    }

    Jifty->handle->begin_transaction();

    # We use effective_id here even though it duplicates information from
    # the links table becasue of the massive performance hit we'd take
    # by trying to do a separate database query for merge info everytime
    # loaded a ticket.

    #update this ticket's effective id to the new ticket's id.
    my ( $id_val, $id_msg ) = $self->__set(
        column => 'effective_id',
        value  => $MergeInto->id()
    );

    unless ($id_val) {
        Jifty->handle->rollback();
        return ( 0, _("Merge failed. Couldn't set effective_id") );
    }

    if ( $self->__value('status') ne 'resolved' ) {

        my ( $status_val, $status_msg ) = $self->__set( column => 'status', value => 'resolved' );

        unless ($status_val) {
            Jifty->handle->rollback();
            Jifty->log->error( _( "%1 couldn't set status to resolved. RT's Database may be inconsistent.", $self ) );
            return ( 0, _("Merge failed. Couldn't set status") );
        }
    }

    # update all the links that point to that old ticket
    my $old_links_to = RT::Model::LinkCollection->new;
    $old_links_to->limit( column => 'target', value => $self->uri );

    my %old_seen;
    while ( my $link = $old_links_to->next ) {
        if ( exists $old_seen{ $link->base . "-" . $link->type } ) {
            $link->delete;
        } elsif ( $link->base eq $MergeInto->uri ) {
            $link->delete;
        } else {

            # First, make sure the link doesn't already exist. then move it over.
            my $tmp = RT::Model::Link->new( current_user => RT->system_user );
            $tmp->load_by_cols(
                base         => $link->base,
                type         => $link->type,
                local_target => $MergeInto->id
            );
            if ( $tmp->id ) {
                $link->delete;
            } else {
                $link->set_target( $MergeInto->uri );
                $link->set_local_target( $MergeInto->id );
            }
            $old_seen{ $link->base . "-" . $link->type } = 1;
        }

    }

    my $old_links_from = RT::Model::LinkCollection->new;
    $old_links_from->limit( column => 'base', value => $self->uri );

    while ( my $link = $old_links_from->next ) {
        if ( exists $old_seen{ $link->type . "-" . $link->target } ) {
            $link->delete;
        }
        if ( $link->target eq $MergeInto->uri ) {
            $link->delete;
        } else {

            # First, make sure the link doesn't already exist. then move it over.
            my $tmp = RT::Model::Link->new( current_user => RT->system_user );
            $tmp->load_by_cols(
                target     => $link->target,
                type       => $link->type,
                local_base => $MergeInto->id
            );
            if ( $tmp->id ) {
                $link->delete;
            } else {
                $link->set_base( $MergeInto->uri );
                $link->set_local_base( $MergeInto->id );
                $old_seen{ $link->type . "-" . $link->target } = 1;
            }
        }

    }

    # Update time fields
    foreach my $type qw(time_estimated time_worked time_left) {

        my $mutator = "set_$type";
        $MergeInto->$mutator( ( $MergeInto->$type() || 0 ) + ( $self->$type() || 0 ) );

    }

    #add all of this ticket's watchers to that ticket.
    foreach my $watcher_type ( $self->roles ) {

        my $group = $self->role_group($watcher_type);
        if ( $group->id ) {
            my $people = $group->members;

            while ( my $watcher = $people->next ) {

                my ( $val, $msg ) = $MergeInto->_add_watcher(
                    type         => $watcher_type,
                    silent       => 1,
                    principal => $watcher->member_id
                );
                Jifty->log->warn($msg) unless ($val);
            }
        }

    }

    #find all of the tickets that were merged into this ticket.
    my $old_mergees = RT::Model::TicketCollection->new;
    $old_mergees->limit(
        column   => 'effective_id',
        operator => '=',
        value    => $self->id
    );

    #   update their effective_id fields to the new ticket's id
    while ( my $ticket = $old_mergees->next() ) {
        my ( $val, $msg ) = $ticket->__set(
            column => 'effective_id',
            value  => $MergeInto->id()
        );
    }

    #make a new link: this ticket is merged into that other ticket.
    $self->add_link( type => 'merged_into', target => $MergeInto->id() );

    $MergeInto->set_last_updated;

    Jifty->handle->commit();
    return ( 1, _("Merge Successful") );
}

=head2 merged

Returns list of tickets' ids that's been merged into this ticket.

=cut

sub merged {
    my $self = shift;

    my $mergees = RT::Model::TicketCollection->new;
    $mergees->limit(
        column    => 'effective_id',
        operator => '=',
        value    => $self->id,
    );
    $mergees->limit(
        column    => 'id',
        operator => '!=',
        value    => $self->id,
    );
    return map $_->id, @{ $mergees->items_array_ref || [] };
}



=head2 owner_obj

Takes nothing and returns an RT::Model::User object of 
this ticket's owner

=cut

sub owner_obj {
    my $self = shift;

    #If this gets ACLed, we lose on a rights check in User.pm and
    #get deep recursion. if we need ACLs here, we need
    #an equiv without ACLs

    my $owner = RT::Model::User->new;
    $owner->load( $self->__value('owner') );

    #Return the owner object
    return ($owner);
}



=head2 owner_as_string

Returns the owner's email address

=cut

sub owner_as_string {
    my $self = shift;
    return ( $self->owner->email );

}



=head2 set_owner

Takes two arguments:
     the id or name of the owner 
and  (optionally) the type of the SetOwner Transaction. It defaults
to 'give'.  'steal' is also a valid option.


=cut

sub set_owner {
    my $self     = shift;
    my $NewOwner = shift;
    my $Type     = shift || "give";

    Jifty->handle->begin_transaction();

    $self->set_last_updated();    # lock the ticket
    $self->load( $self->id );     # in case $self changed while waiting for lock

    my $old_owner_obj = $self->owner;

    my $new_owner_obj = RT::Model::User->new;
    $new_owner_obj->load($NewOwner);
    unless ( $new_owner_obj->id ) {
        Jifty->handle->rollback();
        return ( 0, _("That user does not exist") );
    }

    # must have ModifyTicket rights
    # or TakeTicket/StealTicket and $NewOwner is self
    # see if it's a take
    if ( $old_owner_obj->id == RT->nobody->id ) {
        unless ( $self->current_user_has_right('ModifyTicket')
            || $self->current_user_has_right('TakeTicket') )
        {
            Jifty->handle->rollback();
            return ( 0, _("Permission Denied") );
        }
    }

    # see if it's a steal
    elsif ($old_owner_obj->id != RT->nobody->id
        && $old_owner_obj->id != $self->current_user->id )
    {

        unless ( $self->current_user_has_right('ModifyTicket')
            || $self->current_user_has_right('StealTicket') )
        {
            Jifty->handle->rollback();
            return ( 0, _("Permission Denied") );
        }
    } else {
        unless ( $self->current_user_has_right('ModifyTicket') ) {
            Jifty->handle->rollback();
            return ( 0, _("Permission Denied") );
        }
    }

    # If we're not stealing and the ticket has an owner and it's not
    # the current user
    if (    $Type ne 'steal'
        and $Type ne 'force'
        and $old_owner_obj->id != RT->nobody->id
        and $old_owner_obj->id != $self->current_user->id )
    {
        Jifty->handle->rollback();
        return ( 0, _("You can only take tickets that are unowned") )
            if $new_owner_obj->id == $self->current_user->id;
        return ( 0, _( "You can only reassign tickets that you own or that are unowned" ) );
    }

    #If we've specified a new owner and that user can't modify the ticket
    elsif ( !$new_owner_obj->has_right( right => 'OwnTicket', object => $self ) ) {
        Jifty->handle->rollback();
        return ( 0, _("That user may not own tickets in that queue") );
    }

    # If the ticket has an owner and it's the new owner, we don't need
    # To do anything
    elsif ( $new_owner_obj->id == $old_owner_obj->id ) {
        Jifty->handle->rollback();
        return ( 0, _("That user already owns that ticket") );
    }

    # Delete the owner in the owner group, then add a new one
    # TODO: is this safe? it's not how we really want the API to work
    # for most things, but it's fast.
    my ( $del_id, $del_msg ) = $self->role_group("owner")->members->first->delete();
    unless ($del_id) {
        Jifty->handle->rollback();
        return ( 0, _("Could not change owner. %1", $del_msg ));
    }
    my ( $add_id, $add_msg ) = $self->role_group("owner")->_add_member(
        principal => $new_owner_obj,
    );
    unless ($add_id) {
        Jifty->handle->rollback();
        return ( 0, _( "Could not change owner: %1", $add_msg ) );
    }

    # We call set twice with slightly different arguments, so
    # as to not have an SQL transaction span two RT transactions

    my ($return, $msg) = $self->_set(
        column             => 'owner',
        value              => $new_owner_obj->id,
        record_transaction => 0,
        time_taken         => 0,
        transaction_type   => $Type,
        check_acl          => 0,                    # don't check acl
    );

    if ( ref($return) and !$return ) {
        Jifty->handle->rollback;
        return ( 0, _("Could not change owner: %1", $msg ) );
    }

    ( my $val, $msg ) = $self->_new_transaction(
        type       => $Type,
        field      => 'owner',
        new_value  => $new_owner_obj->id,
        old_value  => $old_owner_obj->id,
        time_taken => 0,
    );

    if ($val) {
        $msg = _( "Owner changed from %1 to %2", $old_owner_obj->name, $new_owner_obj->name );
    } else {
        Jifty->handle->rollback();
        return ( 0, $msg );
    }

    Jifty->handle->commit();

    return ( $val, $msg );
}



=head2 take

A convenince method to set the ticket's owner to the current user

=cut

sub take {
    my $self = shift;
    return ( $self->set_owner( $self->current_user->id, 'take' ) );
}



=head2 untake

Convenience method to set the owner to 'nobody' if the current user is the owner.

=cut

sub untake {
    my $self = shift;
    return ( $self->set_owner( RT->nobody->user_object->id, 'untake' ) );
}

=head2 steal

A convenience method to change the owner of the current ticket to the
current user. Even if it's owned by another user.

=cut

sub steal {
    my $self = shift;

    if ( $self->owner->id == $self->current_user->id ) {
        return ( 0, _("You already own this ticket") );
    } else {
        return ( $self->set_owner( $self->current_user->id, 'steal' ) );

    }

}

=head2 validate_status STATUS

Takes a string. Returns true if that status is a valid status for this ticket.
Returns false otherwise.

=cut

sub validate_status {
    my $self     = shift;
    my $status   = shift;
    my $other    = shift;
    my $metadata = shift;

    my $queue_obj = RT::Model::Queue->load($self->queue_id || $other->{queue});

    if ( $queue_obj->status_schema->is_valid($status) ) {
        return 1;
    }

    return undef;
}



=head2 set_status STATUS

Set this ticket's status.

Alternatively, you can pass in a list of named parameters
(status => STATUS, force => FORCE).  If FORCE is true,
ignore unresolved dependencies and force a status change.

=cut

sub set_status {
    my $self = shift;
    my %args;

    if ( @_ == 1 ) {
        $args{status} = shift;
    } else {
        %args = (@_);
    }

    #Check ACL
    if ( $args{status} eq 'deleted' ) {
        unless ( $self->current_user_has_right('DeleteTicket') ) {
            return ( 0, _('Permission Denied') );
        }
    } else {
        unless ( $self->current_user_has_right('ModifyTicket') ) {
            return ( 0, _('Permission Denied') );
        }
    }

    my $schema = $self->queue->status_schema;
    unless ( $schema->is_valid( $args{'status'} ) ) {
        return ( 0, _( "'%1' is an invalid value for status", $args{'status'} ) );
    }

    if (   !$args{force}
        && $schema->is_inactive( $args{'status'} )
        && $self->has_unresolved_dependencies )
    {
        return ( 0, _('That ticket has unresolved dependencies') );
    }

    my $now = RT::DateTime->now;

    #If we're changing the status from intial to non-initial, record that we've started
    if ( $schema->is_initial( $self->status ) && !$schema->is_initial( $args{status} ) )  {
        $self->_set(
            column             => 'started',
            value              => $now,
            record_transaction => 0
        );
    }

    #When we close a ticket, set the 'resolved' attribute to now.
    # It's misnamed, but that's just historical.
    if ( $schema->is_inactive( $args{status} ) ) {
        $self->_set(
            column             => 'resolved',
            value              => $now,
            record_transaction => 0
        );
    }

    #Actually update the status
    my ( $val, $msg ) = $self->_set(
        column           => 'status',
        value            => $args{status},
        time_taken       => 0,
        check_acl        => 0,
    );

    return ( $val, $msg );
}

=head2 set_told ISO  [TIMETAKEN]

Updates the told and records a transaction

=cut

sub set_told {
    my $self = shift;
    my $told;
    $told = shift if (@_);
    my $timetaken = shift || 0;

    unless ( $self->current_user_has_right('ModifyTicket') ) {
        return ( 0, _("Permission Denied") );
    }

    my $datetold;
    if ($told) {
        $datetold = RT::DateTime->new_from_string($told);
    } else {
        $datetold = RT::DateTime->now;
    }

    return (
        $self->_set(
            column           => 'told',
            value            => $datetold->iso,
            time_taken       => $timetaken,
        )
    );
}

=head2 _set_told

Updates the told without a transaction or acl check. Useful when we're sending replies.

=cut

sub _set_told {
    my $self = shift;

    #use __set to get no ACLs ;)
    return (
        $self->__set(
            column => 'told',
            value  => RT::DateTime->now(),
        )
    );
}

=head2 seen_up_to


=cut

sub seen_up_to {
    my $self = shift;
    my $uid  = $self->current_user->id;
    my $attr = $self->first_attribute( "User-" . $uid . "-SeenUpTo" );
    return if $attr && $attr->content gt $self->last_updated;

    my $txns = $self->transactions;
    $txns->limit( column => 'type',    value    => 'comment' );
    $txns->limit( column => 'type',    value    => 'correspond' );
    $txns->limit( column => 'creator', operator => '!=', value => $uid );
    $txns->limit(
        column   => 'created',
        operator => '>',
        value    => $attr->content
    ) if $attr;
    $txns->rows_per_page(1);
    return $txns->first;
}


=head2 transaction_batch

  Returns an array reference of all transactions created on this ticket during
  this ticket object's lifetime, or undef if there were none.

  Only works when the C<use_transaction_batch> config option is set to true.

=cut

sub transaction_batch {
    my $self = shift;
    return $self->{_transaction_batch};
}

sub DESTROY {
    my $self = shift;

    # DESTROY methods need to localize $@, or it may unset it.  This
    # causes $m->abort to not bubble all of the way up.  See perlbug
    # http://rt.perl.org/rt3/Ticket/Display.html?id=17650
    local $@;

    # The following line eliminates reentrancy.
    # It protects against the fact that perl doesn't deal gracefully
    # when an object's refcount is changed in its destructor.
    return if $self->{_Destroyed}++;

    my $batch = $self->transaction_batch or return;
    return unless @$batch;

    my $ticket = RT::Model::Ticket->new( current_user => RT::CurrentUser->superuser );
    my ($ok, $msg) = $ticket->load( $self->id );
    warn "Unable to load ticket #" . $self->id . " for batch processing" if  !$ok;

    # Entry point of the rule system
    my $rules = RT::Ruleset->find_all_rules(
        stage           => 'transaction_batch',
        ticket_obj      => $ticket,
        transaction_obj => $batch->[0],
        type            => join( ',', grep defined, map $_->type, grep defined, @{$batch} )
    );
    RT::Ruleset->commit_rules($rules);
}



sub _set {
    my $self = shift;

    my %args = (
        column             => undef,
        value              => undef,
        time_taken         => 0,
        record_transaction => 1,
        update_ticket      => 1,
        check_acl          => 1,
        transaction_type   => 'set',
        @_
    );

    if ( $args{'check_acl'} ) {
        unless ( $self->current_user_has_right('ModifyTicket') ) {
            return ( 0, _("Permission Denied") );
        }
    }

    unless ( $args{'update_ticket'} || $args{'record_transaction'} ) {
        Jifty->log->error( "Ticket->_set called without a mandate to record an update or update the ticket" );
        return ( 0, _("Internal Error") );
    }

    #if the user is trying to modify the record

    #Take care of the old value we really don't want to get in an ACL loop.
    # so ask the super::_value
    my $Old = $self->SUPER::_value( $args{'column'} );

    if ( $Old && $args{'value'} && $Old eq $args{'value'} ) {

        return ( 0, _("That is already the current value") );
    }
    my ($return);
    if ( $args{'update_ticket'} ) {

        #Set the new value
        $return = $self->SUPER::_set(
            column => $args{'column'},
            value  => $args{'value'}
        );

        #If we can't actually set the field to the value, don't record
        # a transaction. instead, get out of here.
        if ( $return->errno ) {
            return ($return);
        }
    }
    if ( $args{'record_transaction'} == 1 ) {

        my ( $Trans, $Msg, $TransObj ) = $self->_new_transaction(
            type       => $args{'transaction_type'},
            field      => $args{'column'},
            new_value  => $args{'value'},
            old_value  => $Old,
            time_taken => $args{'time_taken'},
        );
        return ( $Trans, scalar $TransObj->brief_description );
    } else {
        return ($return);
    }
}



=head2 _value

Takes the name of a table column.
Returns its value as a string, if the user passes an ACL check

=cut

sub _value {

    my $self   = shift;
    my $column = shift;

    #if the column is public, return it.
    if (1) {    # $self->_accessible( $column, 'public' ) ) {

        #Jifty->log->debug("Skipping ACL check for $column");
        return ( $self->SUPER::_value($column) );

    }

    #If the current user doesn't have ACLs, don't let em at it.

    unless ( $self->current_user_has_right('ShowTicket') ) {
        return (undef);
    }
    return ( $self->SUPER::_value($column) );

}



=head2 _update_time_taken

This routine will increment the time_worked counter. it should
only be called from _new_transaction 

=cut

sub _update_time_taken {
    my $self    = shift;
    my $Minutes = shift;
    my ($Total);

    $Total = $self->SUPER::_value("time_worked");
    $Total = ( $Total || 0 ) + ( $Minutes || 0 );
    $self->SUPER::_set(
        column => "time_worked",
        value  => $Total
    );

    return ($Total);
}





=head2 current_user_has_right

  Takes the textual name of a Ticket scoped right (from RT::Model::ACE) and returns
1 if the user has that right. It returns 0 if the user doesn't have that right.

=cut

sub current_user_has_right {
    my $self  = shift;
    my $right = shift;

    return $self->current_user->principal->has_right(
        object => $self,
        right  => $right,
    );

}



=head2 has_right

 Takes a paramhash with the attributes 'right' and 'principal'
  'right' is a ticket-scoped textual right from RT::Model::ACE 
  'principal' is an RT::Model::User object

  Returns 1 if the principal has the right. Returns undef if not.

=cut

sub has_right {
    my $self = shift;
    my %args = (
        right     => undef,
        principal => undef,
        @_
    );

    unless (( defined $args{'principal'} )
        and ( ref( $args{'principal'} ) ) )
    {
        Carp::cluck("Principal attrib undefined for Ticket::has_right");
        Jifty->log->fatal("Principal attrib undefined for Ticket::has_right");
        return (undef);
    }

    return (
        $args{'principal'}->has_right(
            object => $self,
            right  => $args{'right'}
        )
    );
}

sub current_user_can_modify_watchers {
    my $self = shift;
    my %args = (
        action    => 'add',
        type      => undef,
        principal => undef,
        email     => undef,
        @_
    );

    # ModifyTicket works in any case
    return 1 if $self->current_user_has_right('ModifyTicket');

    # if it's a new user in the system then user must have ModifyTicket
    return 0 unless $args{'principal'};
    # If the watcher isn't the current user then the current user has no right
    return 0 unless $self->current_user->id == (blessed $args{'principal'}? $args{'principal'}->id : $args{'principal'});

    #  If it's an admin_cc and they don't have 'WatchAsadmin_cc', bail
    if ( $args{'type'} eq 'admin_cc' ) {
        return 0 unless $self->current_user_has_right('WatchAsadmin_cc');
    }

    #  otherwise check 'Watch'
    else {
        return 0 unless $self->current_user_has_right('Watch');
    }
    return 1;
}



=head2 reminders

Return the Reminders object for this ticket. (It's an RT::Reminders object.)
It isn't acutally a searchbuilder collection itself.

=cut

sub reminders {
    my $self = shift;

    unless ( $self->{'__reminders'} ) {
        $self->{'__reminders'} = RT::Reminders->new;
        $self->{'__reminders'}->ticket( $self->id );
    }
    return $self->{'__reminders'};

}


=head2 transactions

  Returns an RT::Model::TransactionCollection object of all transactions on this ticket

=cut

sub transactions {
    my $self = shift;

    my $transactions = RT::Model::TransactionCollection->new;

    #If the user has no rights, return an empty object
    if ( $self->current_user_has_right('ShowTicket') ) {
        $transactions->limit_to_ticket( $self->id );

        # if the user may not see comments do not return them
        unless ( $self->current_user_has_right('ShowTicketcomments') ) {
            $transactions->limit(
                subclause => 'acl',
                column    => 'type',
                operator  => '!=',
                value     => "comment"
            );
            $transactions->limit(
                subclause        => 'acl',
                column           => 'type',
                operator         => '!=',
                value            => "comment_email_record",
                entry_aggregator => 'AND'
            );

        }
    }

    return ($transactions);
}



=head2 transaction_custom_fields

    Returns the custom fields that transactions on tickets will have.

=cut

sub transaction_custom_fields {
    my $self = shift;
    return $self->queue->ticket_transaction_custom_fields;
}



=head2 custom_field_values

# Do name => id mapping (if needed) before falling back to
# RT::Record's custom_field_values

See L<RT::Record>

=cut

sub custom_field_values {
    my $self  = shift;
    my $field = shift;
    return $self->SUPER::custom_field_values($field)
      if !$field || $field =~ /^\d+$/;

    my $cf = RT::Model::CustomField->new;
    $cf->load_by_name_and_queue( name => $field, queue => $self->queue );
    unless ( $cf->id ) {
        $cf->load_by_name_and_queue( name => $field, queue => 0 );
    }

    # If we didn't find a valid cfid, give up.
    return RT::Model::ObjectCustomFieldValueCollection->new
      unless $cf->id;

    return $self->SUPER::custom_field_values( $cf->id );
}



=head2 custom_field_lookup_type

Returns the RT::Model::Ticket lookup type, which can be passed to 
RT::Model::CustomField->create() via the 'lookup_type' hash key.

=cut


sub custom_field_lookup_type {
    "RT::Model::Queue-RT::Model::Ticket";
}

=head2 aclequivalenceobjects

This method returns a list of objects for which a user's rights also apply
to this ticket. Generally, this is only the ticket's queue, but some RT 
extensions may make other objects availalbe too.

This method is called from L<RT::Model::Principal/has_right>.

=cut

sub acl_equivalence_objects {
    my $self = shift;
    return $self->queue;

}

sub canonicalize_queue {
    my $self  = shift;
    my $queue = shift;

    my $queue_obj = RT::Model::Queue->load($queue);
    return $queue_obj->id if $queue_obj->id;

    return undef;
}

1;

=head1 AUTHOR

Jesse Vincent, jesse@bestpractical.com

=head1 SEE ALSO

RT

=cut

