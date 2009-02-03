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
# Portions Copyright 2000 Tobias Brox <tobix@cpan.org>

package RT::ScripAction::SendEmail;

use strict;
use warnings;

use base 'RT::ScripAction';

use MIME::Words qw(encode_mimeword);

use RT::EmailParser;
use RT::Interface::Email;
use Email::Address;
our @EMAIL_RECIPIENT_HEADERS = qw(To Cc Bcc);

=head1 name

RT::ScripAction::SendEmail - An Action which users can use to send mail 
or can subclassed for more specialized mail sending behavior. 
RT::ScripAction::AutoReply is a good example subclass.

=head1 SYNOPSIS

  use base 'RT::ScripAction::SendEmail';

=head1 description

Basically, you create another module RT::ScripAction::YourAction which ISA
RT::ScripAction::SendEmail.

=head1 METHODS

=head2 clean_slate

Cleans class-wide options, like L</SquelchMailTo> or L</AttachTickets>.

=cut

sub clean_slate {
    my $self = shift;
    $self->squelch_mail_to(undef);
    $self->attach_tickets(undef);
}

=head2 commit

Sends the prepared message and writes outgoing record into DB if the feature is
activated in the config.

=cut

sub commit {
    my $self = shift;

    $self->defer_digest_recipients() if RT->config->get('RecordOutgoingEmail');
    my $message = $self->template_obj->mime_obj;

    my $orig_message;
    if (   RT->config->get('RecordOutgoingEmail')
        && RT->config->get('GnuPG')->{'enable'} )
    {

        # it's hacky, but we should know if we're going to crypt things
        my $attachment = $self->transaction_obj->attachments->first;

        my %crypt;
        foreach my $argument (qw(sign encrypt)) {
            if ( $attachment
                && defined $attachment->get_header("X-RT-$argument") )
            {
                $crypt{$argument} = $attachment->get_header("X-RT-$argument");
            } else {
                $crypt{$argument} = $self->ticket_obj->queue->$argument();
            }
        }
        if ( $crypt{'sign'} || $crypt{'encrypt'} ) {
            $orig_message = $message->dup;
        }
    }

    my ($ret) = $self->send_message($message);
    if ( $ret > 0 && RT->config->get('RecordOutgoingEmail') ) {
        if ($orig_message) {
            $message->attach(
                Type        => 'application/x-rt-original-message',
                Disposition => 'inline',
                Data        => $orig_message->as_string,
            );
        }
        $self->record_outgoing_mail_transaction($message);
        $self->record_deferred_recipients();
    }

    return ( abs $ret );
}

=head2 prepare

Builds an outgoing email we're going to send using scrip's template.

=cut

sub prepare {
    my $self = shift;

    my ( $result, $message ) = $self->template_obj->parse(
        argument        => $self->argument,
        ticket_obj      => $self->ticket_obj,
        transaction_obj => $self->transaction_obj
    );
    if ( !$result ) {
        return (undef);
    }

    my $mime_obj = $self->template_obj->mime_obj;

    # Header
    $self->set_rt_special_headers();

    $self->remove_inappropriate_recipients();

    my %seen;
    foreach my $type (@EMAIL_RECIPIENT_HEADERS) {
        @{ $self->{$type} } = grep defined && length && !$seen{ lc $_ }++,
          @{ $self->{$type} };
    }

    # Go add all the Tos, Ccs and Bccs that we need to to the message to
    # make it happy, but only if we actually have values in those arrays.

    # TODO: We should be pulling the recipients out of the template and shove them into To, Cc and Bcc

    for my $header (@EMAIL_RECIPIENT_HEADERS) {

        $self->set_header( $header, join( ', ', @{ $self->{$header} } ) )
          if ( !$mime_obj->head->get($header)
            && $self->{$header}
            && @{ $self->{$header} } );
    }

    # PseudoTo (fake to headers) shouldn't get matched for message recipients.
    # If we don't have any 'To' header (but do have other recipients), drop in
    # the pseudo-to header.
    $self->set_header( 'To', join( ', ', @{ $self->{'PseudoTo'} } ) )
        if $self->{'PseudoTo'}
            && @{ $self->{'PseudoTo'} }
            && !$mime_obj->head->get('To')
            && ( $mime_obj->head->get('Cc') or $mime_obj->head->get('Bcc') );

    # We should never have to set the MIME-Version header
    $self->set_header( 'MIME-Version', '1.0' );

    # fsck.com #5959: Since RT sends 8bit mail, we should say so.
    $self->set_header( 'Content-Transfer-Encoding', '8bit' );

    # For security reasons, we only send out textual mails.
    foreach my $part ( grep !$_->is_multipart, $mime_obj->parts_DFS ) {
        my $type = $part->mime_type || 'text/plain';
        $type = 'text/plain' unless RT::I18N::is_textual_content_type($type);
        $part->head->mime_attr( "Content-Type"         => $type );
        $part->head->mime_attr( "Content-Type.charset" => 'utf-8' );
    }

    RT::I18N::set_mime_entity_to_encoding( $mime_obj, RT->config->get('EmailOutputEncoding'), 'mime_words_ok', );

    # Build up a MIME::Entity that looks like the original message.
    $self->add_attachments if $mime_obj->head->get('RT-Attach-Message');

    $self->add_tickets;

    my $attachment = $self->transaction_obj->attachments->first;
    if ( $attachment
        && !( $attachment->get_header('X-RT-Encrypt') || $self->ticket_obj->queue->encrypt ) )
    {
        $attachment->set_header( 'X-RT-Encrypt' => 1 )
            if $attachment->get_header("X-RT-Incoming-Encryption")
                || '' eq 'Success';
    }

    return $result;
}

=head2 to

Returns an array of L<Email::Address> objects containing all the To: recipients for this notification

=cut

sub to {
    my $self = shift;
    return ( $self->addresses_from_header('To') );
}

=head2 cc

Returns an array of L<Email::Address> objects containing all the Cc: recipients for this notification

=cut

sub cc {
    my $self = shift;
    return ( $self->addresses_from_header('Cc') );
}

=head2 bcc

Returns an array of L<Email::Address> objects containing all the Bcc: recipients for this notification

=cut

sub bcc {
    my $self = shift;
    return ( $self->addresses_from_header('Bcc') );

}

sub addresses_from_header {
    my $self      = shift;
    my $field     = shift;
    my $header    = $self->template_obj->mime_obj->head->get($field);
    my @addresses = Email::Address->parse($header);

    return (@addresses);
}

=head2 send_message mime_obj

sends the message using RT's preferred API.
TODO: Break this out to a separate module

=cut

sub send_message {

    # DO NOT SHIFT @_ in this subroutine.  It breaks Hook::LexWrap's
    # ability to pass @_ to a 'post' routine.
    my ( $self, $mime_obj ) = @_;

    my $msgid = $mime_obj->head->get('Message-ID');
    chomp $msgid;

    $self->scrip_action_obj->{_Message_ID}++;

    Jifty->log->info( $msgid . " #" . $self->ticket_obj->id . "/" .
            $self->transaction_obj->id . " - Scrip "
            . ( $self->scrip_obj->id || '#rule' ) . " "
            . ( $self->scrip_obj->description || '' ) );

    my $status = RT::Interface::Email::send_email(
        entity      => $mime_obj,
        ticket      => $self->ticket_obj,
        transaction => $self->transaction_obj,
    );

    return $status unless ( $status > 0 || exists $self->{'Deferred'} );
    

    my $success = $msgid . " sent ";
    foreach (@EMAIL_RECIPIENT_HEADERS) {
        my $recipients = $mime_obj->head->get($_);
        $success .= " $_: " . $recipients if $recipients;
    }

    if ( exists $self->{'Deferred'} ) {
        for (qw(daily weekly susp)) {
            $success .=
              "\nBatched email $_ for: "
              . join( ", ", keys %{ $self->{'Deferred'}{$_} } )
              if exists $self->{'Deferred'}{$_};
        }
    }

    $success =~ s/\n//g;

    Jifty->log->info($success);

    return (1);
}

=head2 add_attachments

Takes any attachments to this transaction and attaches them to the message
we're building.

=cut

sub add_attachments {
    my $self = shift;

    my $mime_obj = $self->template_obj->mime_obj;

    $mime_obj->head->delete('RT-Attach-Message');

    my $attachments = RT::Model::AttachmentCollection->new( current_user => RT->system_user );
    $attachments->limit(
        column => 'transaction_id',
        value  => $self->transaction_obj->id
    );

    # Don't attach anything blank
    $attachments->limit_not_empty;
    $attachments->order_by( column => 'id' );

    # We want to make sure that we don't include the attachment that's
    # being used as the "Content" of this message" unless that attachment's
    # content type is not like text/...
    my $transaction_content_obj = $self->transaction_obj->content_obj;

    if (   $transaction_content_obj
        && $transaction_content_obj->content_type =~ m{text/}i )
    {
        # If this was part of a multipart/alternative, skip all of the kids
        my $parent = $transaction_content_obj->parent_obj;
        if (    $parent
            and $parent->id
            and $parent->content_type eq "multipart/alternative" )
        {
            $attachments->limit(
                entry_aggregator => 'AND',
                column           => 'parent',
                operator        => '!=',
                value           => $parent->id,
            );
        }
        else {
            $attachments->limit(
                entry_aggregator => 'AND',
                column           => 'id',
                operator        => '!=',
                value           => $transaction_content_obj->id,
            );
        }
    }

    # attach any of this transaction's attachments
    my $seen_attachment = 0;
    while ( my $attach = $attachments->next ) {
        if ( !$seen_attachment ) {
            $mime_obj->make_multipart( 'mixed', Force => 1 );
            $seen_attachment = 1;
        }
        $self->add_attachment($attach);
    }

}

=head2 add_attachment $attachment

Takes one attachment object of L<RT::Model::Attachmment> class and attaches it to the message
we're building.

=cut

sub add_attachment {
    my $self     = shift;
    my $attach   = shift;
    my $mime_obj = shift || $self->template_obj->mime_obj;

    $mime_obj->attach(
        Type     => $attach->content_type,
        Charset  => $attach->original_encoding,
        Data     => $attach->original_content,
        Filename => defined( $attach->filename )
        ? $self->mime_encode_string( $attach->filename, RT->config->get('EmailOutputEncoding') )
        : undef,
        'RT-Attachment:' => $self->ticket_obj->id . "/" . $self->transaction_obj->id . "/" . $attach->id,
        Encoding         => '-SUGGEST',
    );
}

=head2 attach_tickets [@IDs]

Returns or set list of ticket's IDs that should be attached to an outgoing message.

B<Note> this method works as a class method and setup things global, so you have to
clean list by passing undef as argument.

=cut

{
    my $list = [];

    sub attach_tickets {
        my $self = shift;
        $list = [ grep defined, @_ ] if @_;
        return @$list;
    }
}

=head2 add_tickets

Attaches tickets to the current message, list of tickets' ids get from
L</AttachTickets> method.

=cut

sub add_tickets {
    my $self = shift;
    $self->add_ticket($_) foreach $self->attach_tickets;
    return;
}

=head2 add_ticket $ID

Attaches a ticket with ID to the message.

Each ticket is attached as multipart entity and all its messages and attachments
are attached as sub entities in order of creation, but only if transaction type
is Create or correspond.

=cut

sub add_ticket {
    my $self = shift;
    my $tid  = shift;

    # XXX: we need a current user here, but who is current user?
    my $attachs = RT::Model::AttachmentCollection->new( current_user => RT->system_user );
    my $txn_alias = $attachs->transaction_alias;
    $attachs->limit(
        alias  => $txn_alias,
        column => 'type',
        value  => 'Create'
    );
    $attachs->limit(
        alias  => $txn_alias,
        column => 'type',
        value  => 'correspond'
    );
    $attachs->limit_by_ticket($tid);
    $attachs->limit_not_empty;
    $attachs->order_by( column => 'Created' );

    my $ticket_mime = MIME::Entity->build(
        Type        => 'multipart/mixed',
        Top         => 0,
        description => "ticket #$tid",
    );
    while ( my $attachment = $attachs->next ) {
        $self->add_attachment( $attachment, $ticket_mime );
    }
    if ( $ticket_mime->parts ) {
        my $email_mime = $self->template_obj->mime_obj;
        $email_mime->make_multipart;
        $email_mime->add_part($ticket_mime);
    }
    return;
}

=head2 record_outgoing_mail_transaction mime_obj

Record a transaction in RT with this outgoing message for future record-keeping purposes

=cut

sub record_outgoing_mail_transaction {
    my $self     = shift;
    my $mime_obj = shift;

    my @parts = $mime_obj->parts;
    my @attachments;
    my @keep;
    foreach my $part (@parts) {
        my $attach = $part->head->get('RT-Attachment');
        if ($attach) {
            Jifty->log->debug("We found an attachment. we want to not record it.");
            push @attachments, $attach;
        } else {
            Jifty->log->debug("We found a part. we want to record it.");
            push @keep, $part;
        }
    }
    $mime_obj->parts( \@keep );
    foreach my $attachment (@attachments) {
        $mime_obj->head->add( 'RT-Attachment', $attachment );
    }

    RT::I18N::set_mime_entity_to_encoding( $mime_obj, 'utf-8', 'mime_words_ok' );

    my $transaction = RT::Model::Transaction->new( current_user => $self->transaction_obj->current_user );

    # XXX: TODO -> Record attachments as references to things in the attachments table, maybe.

    my $type;
    if ( $self->transaction_obj->type eq 'comment' ) {
        $type = 'comment_email_record';
    } else {
        $type = 'email_record';
    }

    my $msgid = $mime_obj->head->get('Message-ID');
    chomp $msgid;

    my ( $id, $msg ) = $transaction->create(
        object          => $self->ticket_obj,
        type            => $type,
        data            => $msgid,
        mime_obj        => $mime_obj,
        activate_scrips => 0
    );

    if ($id) {
        $self->{'OutgoingMailTransaction'} = $id;
    } else {
        Jifty->log->warn("Could not record outgoing message transaction: $msg");
    }
    return $id;
}

=head2 set_rtspecialheaders 

This routine adds all the random headers that RT wants in a mail message
that don't matter much to anybody else.

=cut

sub set_rt_special_headers {
    my $self = shift;

    $self->set_subject();
    $self->set_subject_token();
    $self->set_header_as_encoding( 'Subject', RT->config->get('EmailOutputEncoding') )
        if ( RT->config->get('EmailOutputEncoding') );
    $self->set_return_address();
    $self->set_references_headers();

    unless ( $self->template_obj->mime_obj->head->get('Message-ID') ) {

        # Get Message-ID for this txn
        my $msgid = "";
        if ( my $msg = $self->transaction_obj->message->first ) {
            $msgid = $msg->get_header("RT-Message-ID")
                || $msg->get_header("Message-ID");
        }

        # If there is one, and we can parse it, then base our Message-ID on it
        if (    $msgid
            and $msgid =~ s/<(rt-.*?-\d+-\d+)\.(\d+)-\d+-\d+\@\QRT->config->get('Organization')\E>$/
                         "<$1." . $self->ticket_obj->id
                          . "-" . $self->scrip_obj->id
                          . "-" . $self->scrip_action_obj->{_Message_ID}
                          . "@" . RT->config->get('Organization') . ">"/eg
            and $2 == $self->ticket_obj->id
            )
        {
            $self->set_header( "Message-ID" => $msgid );
        } else {
            $self->set_header(
                'Message-ID' => RT::Interface::Email::gen_message_id(
                    ticket       => $self->ticket_obj,
                    scrip        => $self->scrip_obj,
                    scrip_action => $self->scrip_action_obj
                ),
            );
        }
    }

    $self->set_header( 'Precedence', "bulk" )
        unless ( $self->template_obj->mime_obj->head->get("Precedence") );

    $self->set_header( 'X-RT-Loop-Prevention', RT->config->get('rtname') );
    $self->set_header( 'RT-Ticket',            RT->config->get('rtname') . " #" . $self->ticket_obj->id() );
    $self->set_header( 'Managed-by',           "RT $RT::VERSION (http://www.bestpractical.com/rt/)" );

    # XXX, TODO: use /ShowUser/ShowUserEntry(or something like that) when it would be
    #            refactored into user's method.
    if ( my $email = $self->transaction_obj->creator_obj->email ) {
        $self->set_header( 'RT-Originator', $email );
    }

}

sub defer_digest_recipients {
    my $self = shift;
    Jifty->log->debug( "Calling SetRecipientDigests for transaction "
          . $self->transaction_obj . ", id "
          . $self->transaction_obj->id );

    # The digest attribute will be an array of notifications that need to
    # be sent for this transaction.  The array will have the following
    # format for its objects.
    # $digest_hash -> {daily|weekly|susp} -> address -> {To|Cc|Bcc}
    #                                     -> sent -> {true|false}
    # The "sent" flag will be used by the cron job to indicate that it has
    # run on this transaction.
    # In a perfect world we might move this hash construction to the
    # extension module itself.
    my $digest_hash = {};

    foreach my $mailfield (@EMAIL_RECIPIENT_HEADERS) {

  # If we have a "PseudoTo", the "To" contains it, so we don't need to access it
        next
          if ( ( $self->{'PseudoTo'} && @{ $self->{'PseudoTo'} } )
            && ( $mailfield eq 'To' ) );
        Jifty->log->debug( "Working on mailfield $mailfield; recipients are "
              . join( ',', @{ $self->{$mailfield} } ) );

        # Store the 'daily digest' folk in an array.
        my ( @send_now, @daily_digest, @weekly_digest, @suspended );

        # Have to get the list of addresses directly from the MIME header
        # at this point.
        Jifty->log->debug( $self->template_obj->mime_obj->head->as_string );
        foreach my $rcpt ( map { $_->address }
            $self->addresses_from_header($mailfield) )
        {
            next unless $rcpt;
            my $user_object = RT::Model::User->new( current_user => RT->system_user);
            $user_object->load_by_email($rcpt);
            if ( !$user_object->id ) {

                # If there's an email address in here without an associated
                # RT user, pass it on through.
                Jifty->log->debug(
"User $rcpt is not associated with an RT user object.  Send mail."
                );
                push( @send_now, $rcpt );
                next;
            }

            my $mailpref = RT->config->get( 'EmailFrequency', $user_object ) || '';
            Jifty->log->debug(
                "Got user mail preference '$mailpref' for user $rcpt");

            if    ( $mailpref =~ /daily/i )   { push( @daily_digest,  $rcpt ) }
            elsif ( $mailpref =~ /weekly/i )  { push( @weekly_digest, $rcpt ) }
            elsif ( $mailpref =~ /suspend/i ) { push( @suspended,     $rcpt ) }
            else                              { push( @send_now,      $rcpt ) }
        }

        # Reset the relevant mail field.
        Jifty->log->debug(
            "Removing deferred recipients from $mailfield: line");
        if (@send_now) {
            $self->set_header( $mailfield, join( ', ', @send_now ) );
        }
        else {    # No recipients!  Remove the header.
            $self->template_obj->mime_obj->head->delete($mailfield);
        }

        # Push the deferred addresses into the appropriate field in
        # our attribute hash, with the appropriate mail header.
        Jifty->log->debug(
            "Setting deferred recipients for attribute creation");
        $digest_hash->{'daily'}->{$_} = { 'header' => $mailfield, _sent => 0 }
          for (@daily_digest);
        $digest_hash->{'weekly'}->{$_} = { 'header' => $mailfield, _sent => 0 }
          for (@weekly_digest);
        $digest_hash->{'susp'}->{$_} = { 'header' => $mailfield, _sent => 0 }
          for (@suspended);
    }

    if ( scalar keys %$digest_hash ) {

        # Save the hash so that we can add it as an attribute to the
        # outgoing email transaction.
        $self->{'Deferred'} = $digest_hash;
    }
    else {
        Jifty->log->debug( "No recipients found for deferred delivery on "
              . "transaction #"
              . $self->transaction_obj->id );
    }
}

sub record_deferred_recipients {
    my $self   = shift;
    return unless exists $self->{'Deferred'};
    
    my $txn_id = $self->{'OutgoingMailTransaction'};
    return unless $txn_id;

    my $txn_obj = RT::Model::Transaction->new;
    $txn_obj->load($txn_id);
    my ( $ret, $msg ) = $txn_obj->add_attribute(
        name    => 'DeferredRecipients',
        content => $self->{'Deferred'}
    );
    Jifty->log->warn(
        "Unable to add deferred recipients to outgoing transaction: $msg")
      unless $ret;

    return ( $ret, $msg );
}

=head2 squelch_mail_to [@ADDRESSES]

Mark ADDRESSES to be removed from list of the recipients. Returns list of the addresses.
To empty list pass undefined argument.

B<Note> that this method can be called as class method and works globaly. Don't forget to
clean this list when blocking is not required anymore, pass undef to do this.

=cut

{
    my $squelch = [];

    sub squelch_mail_to {
        my $self = shift;
        if (@_) {
            $squelch = [ grep defined, @_ ];
        }
        return @$squelch;
    }
}

=head2 remove_inappropriate_recipients

Remove addresses that are RT addresses or that are on this transaction's blacklist

=cut

sub remove_inappropriate_recipients {
    my $self = shift;

    my @blacklist = ();

    # If there are no recipients, don't try to send the message.
    # If the transaction has content and has the header RT-Squelch-Replies-To

    my $msgid = $self->template_obj->mime_obj->head->get('Message-ID');

    if ( my $attachment = $self->transaction_obj->attachments->first ) {
        if ( $attachment->get_header('RT-DetectedAutoGenerated') ) {

            # What do we want to do with this? It's probably (?) a bounce
            # caused by one of the watcher addresses being broken.
            # Default ("true") is to redistribute, for historical reasons.

            if ( !RT->config->get('RedistributeAutoGeneratedMessages') ) {

                # Don't send to any watchers.
                @{ $self->{$_} } = () for (@EMAIL_RECIPIENT_HEADERS);

                Jifty->log->info( $msgid
                      . " The incoming message was autogenerated. "
                      . "Not redistributing this message based on site configuration."
                );
            } elsif ( RT->config->get('RedistributeAutoGeneratedMessages') eq 'privileged' ) {

                # Only send to "privileged" watchers.
                #

                foreach my $type (@EMAIL_RECIPIENT_HEADERS) {

                    foreach my $addr ( @{ $self->{$type} } ) {
                        my $user = RT::Model::User->new( current_user => RT->system_user );
                        $user->load_by_email($addr);
                        push @blacklist, $addr if ( !$user->privileged );

                    }
                }

                Jifty->log->info( $msgid
                      . " The incoming message was autogenerated. "
                      . "Not redistributing this message to unprivileged users based on site configuration."
                );

            }

        }

        if ( my $squelch = $attachment->get_header('RT-Squelch-Replies-To') ) {
            push @blacklist, split( /,/, $squelch );
        }
    }

    # Let's grab the SquelchMailTo attribue and push those entries into the @blacklist
    push @blacklist, map $_->content, $self->ticket_obj->squelch_mail_to;
    push @blacklist, $self->squelch_mail_to;

    # Cycle through the people we're sending to and pull out anyone on the
    # system blacklist

# Trim leading and trailing spaces. # Todo - we should really be canonicalizing all addresses
    s/\s//g foreach @blacklist;
    
    foreach my $type (@EMAIL_RECIPIENT_HEADERS) {
        my @addrs;
        foreach my $addr ( @{ $self->{$type} } ) {

         # Weed out any RT addresses. We really don't want to talk to ourselves!
         # If we get a reply back, that means it's not an RT address
            if ( !RT::EmailParser->cull_rt_addresses($addr) ) {
                Jifty->log->info( $msgid
                      . "$addr appears to point to this RT instance. Skipping"
                );
                next;
            }
            if ( grep /^\Q$addr\E$/, @blacklist ) {
                Jifty->log->info( $msgid
                      . "$addr was blacklisted for outbound mail on this transaction. Skipping"
                );
                next;
            }
            push @addrs, $addr;
        }
        @{ $self->{$type} } = @addrs;
    }
}

=head2 set_return_address is_comment => BOOLEAN

Calculate and set From and Reply-To headers based on the is_comment flag.

=cut

sub set_return_address {

    my $self = shift;
    my %args = (
        is_comment    => 0,
        friendly_name => undef,
        @_
    );

    # From and Reply-To
    # $args{is_comment} should be set if the comment address is to be used.
    my $replyto;

    if ( $args{'is_comment'} ) {
        $replyto = $self->ticket_obj->queue->comment_address
            || RT->config->get('CommentAddress');
    } else {
        $replyto = $self->ticket_obj->queue->correspond_address
            || RT->config->get('CorrespondAddress');
    }

    unless ( $self->template_obj->mime_obj->head->get('From') ) {
        if ( RT->config->get('UseFriendlyFromLine') ) {
            my $friendly_name = $args{friendly_name};

            unless ($friendly_name) {
                $friendly_name =
                  $self->transaction_obj->creator_obj->friendly_name;
                if ( $friendly_name =~ /^"(.*)"$/ ) {    # a quoted string
                    $friendly_name = $1;
                }
            }

            $friendly_name =~ s/"/\\"/g;
            $self->set_header( 'From', sprintf( RT->config->get('FriendlyFromLineFormat'), $self->mime_encode_string( $friendly_name, RT->config->get('EmailOutputEncoding') ), $replyto ), );
        } else {
            $self->set_header( 'From', $replyto );
        }
    }

    unless ( $self->template_obj->mime_obj->head->get('Reply-To') ) {
        $self->set_header( 'Reply-To', "$replyto" );
    }

}

=head2 set_header column, value

Set the column of the current MIME object into value.

=cut

sub set_header {
    my $self  = shift;
    my $field = shift;
    my $val   = shift;

    chomp $val;
    chomp $field;
    my $head = $self->template_obj->mime_obj->head;
    $head->fold_length( $field, 10000 );
    $head->replace( $field, $val );
    return $head->get($field);
}

=head2 set_subject

This routine sets the subject. it does not add the rt tag. That gets done elsewhere
If subject is already defined via template, it uses that. otherwise, it tries to get
the transaction's subject.

=cut 

sub set_subject {
    my $self = shift;
    my $subject;

    if ( $self->template_obj->mime_obj->head->get('Subject') ) {
        return ();
    }

    my $message = $self->transaction_obj->attachments;
    $message->rows_per_page(1);
    if ( $self->{'subject'} ) {
        $subject = $self->{'subject'};
    } elsif ( my $first = $message->first ) {
        my $tmp = $first->get_header('Subject');
        $subject = defined $tmp ? $tmp : $self->ticket_obj->subject;
    } else {
        $subject = $self->ticket_obj->subject();
    }

    $subject =~ s/(\r\n|\n|\s)/ /gi;

    chomp $subject;
    $self->set_header( 'Subject', $subject );

}

=head2 set_subject_token

This routine fixes the RT tag in the subject. It's unlikely that you want to overwrite this.

=cut

sub set_subject_token {
    my $self = shift;

    my $head = $self->template_obj->mime_obj->head;
    $head->replace(
        Subject => RT::Interface::Email::add_subject_tag(
            Encode::decode_utf8( $head->get('Subject') ),
            $self->ticket_obj,
        ),
    );
}

=head2 set_references_headers

Set References and In-Reply-To headers for this message.

=cut

sub set_references_headers {
    my $self = shift;
    my ( @in_reply_to, @references, @msgid );

    if ( my $top = $self->transaction_obj->message->first ) {
        @in_reply_to = split( /\s+/m, $top->get_header('In-Reply-To') || '' );
        @references  = split( /\s+/m, $top->get_header('References')  || '' );
        @msgid       = split( /\s+/m, $top->get_header('Message-ID')  || '' );
    } else {
        return (undef);
    }

    # There are two main cases -- this transaction was Created with
    # the RT Web UI, and hence we want to *not* append its Message-ID
    # to the References and In-Reply-To.  OR it came from an outside
    # source, and we should treat it as per the RFC
    my $org = RT->config->get('Organization');
    if ( "@msgid" =~ /<(rt-.*?-\d+-\d+)\.(\d+)-0-0\@\Q$org\E>/ ) {

        # Make all references which are internal be to version which we
        # have sent out

        for ( @references, @in_reply_to ) {
            s/<(rt-.*?-\d+-\d+)\.(\d+-0-0)\@\Q$org\E>$/
          "<$1." . $self->ticket_obj->id .
             "-" . $self->scrip_obj->id .
             "-" . $self->scrip_action_obj->{_Message_ID} .
             "@" . $org . ">"/eg
        }

        # In reply to whatever the internal message was in reply to
        $self->set_header( 'In-Reply-To', join( " ", (@in_reply_to) ) );

        # Default the references to whatever we're in reply to
        @references = @in_reply_to unless @references;

        # References are unchanged from internal
    } else {

        # In reply to that message
        $self->set_header( 'In-Reply-To', join( " ", (@msgid) ) );

        # Default the references to whatever we're in reply to
        @references = @in_reply_to unless @references;

        # Push that message onto the end of the references
        push @references, @msgid;
    }

    # Push pseudo-ref to the front
    my $pseudo_ref = $self->pseudo_reference;
    @references = ( $pseudo_ref, grep { $_ ne $pseudo_ref } @references );

    # If there are more than 10 references headers, remove all but the
    # first four and the last six (Gotta keep this from growing
    # forever)
    splice( @references, 4, -6 ) if ( $#references >= 10 );

    # Add on the references
    $self->set_header( 'References', join( " ", @references ) );
    $self->template_obj->mime_obj->head->fold_length( 'References', 80 );

}

=head2 pseudo_reference

Returns a fake Message-ID: header for the ticket to allow a base level of threading

=cut

sub pseudo_reference {

    my $self       = shift;
    my $pseudo_ref = '<RT-Ticket-' . $self->ticket_obj->id . '@' . RT->config->get('Organization') . '>';
    return $pseudo_ref;
}

=head2 set_header_as_encoding($field_name, $charset_encoding)

This routine converts the field into specified charset encoding.

=cut

sub set_header_as_encoding {
    my $self = shift;
    my ( $field, $enc ) = ( shift, shift );

    my $head = $self->template_obj->mime_obj->head;

    if ( lc($field) eq 'from' and RT->config->get('SMTPFrom') ) {
        $head->replace( $field, RT->config->get('SMTPFrom') );
        return;
    }

    my $value = $head->get($field);

    $value = $self->mime_encode_string( $value, $enc );

    $head->replace( $field, $value );

}

=head2 mimeencode_string STRING ENCODING

Takes a string and a possible encoding and returns the string wrapped in MIME goo.

=cut

sub mime_encode_string {
    my $self  = shift;
    my $value = shift;

    # using RFC2047 notation, sec 2.
    # encoded-word = "=?" charset "?" encoding "?" encoded-text "?="
    my $charset  = shift;
    my $encoding = 'B';

    # An 'encoded-word' may not be more than 75 characters long
    #
    # MIME encoding increases 4/3*(number of bytes), and always in multiples
    # of 4. Thus we have to find the best available value of bytes available
    # for each chunk.
    #
    # First we get the integer max which max*4/3 would fit on space.
    # Then we find the greater multiple of 3 lower or equal than $max.
    my $max = int( ( ( 75 - length( '=?' . $charset . '?' . $encoding . '?' . '?=' ) ) * 3 ) / 4 );
    $max = int( $max / 3 ) * 3;

    chomp $value;

    if ( $max <= 0 ) {

        # gives an error...
        Jifty->log->fatal("Can't encode! Charset or encoding too big.");
        return ($value);
    }

    return ($value) unless $value =~ /[^\x20-\x7e]/;

    $value =~ s/\s*$//;

    # we need perl string to split thing char by char
    Encode::_utf8_on($value) unless Encode::is_utf8($value);

    my ( $tmp, @chunks ) = ( '', () );
    while ( length $value ) {
        my $char = substr( $value, 0, 1, '' );
        my $octets = Encode::encode( $charset, $char );
        if ( length($tmp) + length($octets) > $max ) {
            push @chunks, $tmp;
            $tmp = '';
        }
        $tmp .= $octets;
    }
    push @chunks, $tmp if length $tmp;

    # encode an join chuncks
    $value = join "\n ", map encode_mimeword( $_, $encoding, $charset ), @chunks;
    return ($value);
}

1;

