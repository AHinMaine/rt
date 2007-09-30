# Portions Copyright 2000 Tobias Brox <tobix@cpan.org> 

=head1 NAME

  RT::Model::Template - RT's template object

=head1 SYNOPSIS

  use RT::Model::Template;

=head1 DESCRIPTION


=head1 METHODS


=cut


package RT::Model::Template;

use strict;
no warnings qw(redefine);

use Text::Template;
use MIME::Entity;
use MIME::Parser;
use File::Temp qw /tempdir/;

sub table { 'Templates'}

use base qw'RT::Record';
use Jifty::DBI::Schema;
use Jifty::DBI::Record schema {
column        Queue => max_length is 11,  type is 'int(11)', default is '0';
column        Name => max_length is 200,  type is 'varchar(200)', default is '';
column        Description => max_length is 255,  type is 'varchar(255)', default is '';
column        Type => max_length is 16,  type is 'varchar(16)', default is '';
column        Language => max_length is 16,  type is 'varchar(16)', default is '';
column        TranslationOf => max_length is 11,  type is 'int(11)', default is '0';
column        Content =>   type is 'blob', default is '';
column        LastUpdated =>   type is 'datetime', default is '';
column        LastUpdatedBy => max_length is 11,  type is 'int(11)', default is '0';
column        Creator => max_length is 11,  type is 'int(11)', default is '0';
column        Created =>   type is 'datetime', default is '';

};


sub _set {
    my $self = shift;
    
    unless ( $self->current_user_has_queue_right('ModifyTemplate') ) {
        return ( 0, $self->loc('Permission Denied') );
    }
    return $self->SUPER::_set( @_ );
}

# }}}

# {{{ sub _value 

=head2 _value

Takes the name of a table column.
Returns its value as a string, if the user passes an ACL check





=cut

sub _value {
    my $self  = shift;

    unless ( $self->current_user_has_queue_right('ShowTemplate') ) {
        return undef;
    }
    return $self->__value( @_ );

}

# }}}

# {{{ sub load

=head2 Load <identifer>

Load a template, either by number or by name

=cut

sub load {
    my $self       = shift;
    my $identifier = shift;
    return undef unless $identifier;

    if ( $identifier =~ /\D/ ) {
        return $self->load_by_cols( 'Name', $identifier );
    }
    return $self->load_by_id( $identifier );
}

# }}}

# {{{ sub loadGlobalTemplate

=head2 LoadGlobalTemplate NAME

Load the global template with the name NAME

=cut

sub loadGlobalTemplate {
    my $self = shift;
    my $id   = shift;

    return ( $self->loadQueueTemplate( Queue => 0, Name => $id ) );
}

# }}}

# {{{ sub loadQueueTemplate

=head2  LoadQueueTemplate (Queue => QUEUEID, Name => NAME)

Loads the Queue template named NAME for Queue QUEUE.

=cut

sub loadQueueTemplate {
    my $self = shift;
    my %args = (
        Queue => undef,
        Name  => undef,
        @_
    );

    return ( $self->load_by_cols( Name => $args{'Name'}, Queue => $args{'Queue'} ) );

}

# }}}

# {{{ sub create

=head2 Create

Takes a paramhash of Content, Queue, Name and Description.
Name should be a unique string identifying this Template.
Description and Content should be the template's title and content.
Queue should be 0 for a global template and the queue # for a queue-specific 
template.

Returns the Template's id # if the create was successful. Returns undef for
unknown database failure.


=cut

sub create {
    my $self = shift;
    my %args = (
        Content     => undef,
        Queue       => 0,
        Description => '[no description]',
        Type        => 'Action', #By default, template are 'Action' templates
        Name        => undef,
        @_
    );

    unless ( $args{'Queue'} ) {
        unless ( $self->current_user->has_right(Right =>'ModifyTemplate', Object => RT->System) ) {
            return ( undef, $self->loc('Permission denied') );
        }
        $args{'Queue'} = 0;
    }
    else {
        my $QueueObj = new RT::Model::Queue( $self->current_user );
        $QueueObj->load( $args{'Queue'} ) || return ( undef, $self->loc('Invalid queue') );
    
        unless ( $QueueObj->current_user_has_right('ModifyTemplate') ) {
            return ( undef, $self->loc('Permission denied') );
        }
        $args{'Queue'} = $QueueObj->id;
    }

    my $result = $self->SUPER::create(
        Content     => $args{'Content'},
        Queue       => $args{'Queue'},
        Description => $args{'Description'},
        Name        => $args{'Name'},
    );

    return ($result);

}

# }}}

# {{{ sub delete

=head2 Delete

Delete this template.

=cut

sub delete {
    my $self = shift;

    unless ( $self->current_user_has_queue_right('ModifyTemplate') ) {
        return ( 0, $self->loc('Permission Denied') );
    }

    return ( $self->SUPER::delete(@_) );
}




=head2 IsEmpty
 
Returns true value if content of the template is empty, otherwise
returns false.

=cut

sub IsEmpty {
     my $self = shift;
    my $content = $self->Content;
    return 0 if defined $content && length $content;
    return 1;
 } 
 
=head2 MIMEObj
 
Returns L<MIME::Entity> object parsed using L</Parse> method. Returns
undef if last call to L</Parse> failed or never be called.
 
=cut

sub MIMEObj {
    my $self = shift;
    return ( $self->{'MIMEObj'} );
}


# {{{ sub Parse 

=head2 Parse

 This routine performs Text::Template parsing on the template and then
 imports the results into a MIME::Entity so we can really use it

 Takes a hash containing Argument, TicketObj, and TransactionObj.

 It returns a tuple of (val, message)
 If val is 0, the message contains an error message

=cut

=head2 Parse
         
This routine performs L<Text::Template> parsing on the template and then
imports the results into a L<MIME::Entity> so we can really use it. Use
L</MIMEObj> method to get the L<MIME::Entity> object.
 
Takes a hash containing Argument, TicketObj, and TransactionObj and other
arguments that will be available in the template's code.
     
It returns a tuple of (val, message). If val is false, the message contains
an error message.
 
=cut

 sub Parse {
     my $self = shift;

    # clear prev MIME object
    $self->{'MIMEObj'} = undef;

     #We're passing in whatever we were passed. it's destined for _ParseContent
     my ($content, $msg) = $self->_ParseContent(@_);
     return ( 0, $msg ) unless defined $content && length $content;

     #Lets build our mime Entity

    my $parser = MIME::Parser->new();

    # On some situations TMPDIR is non-writable. sad but true.
    $parser->output_to_core(1);
    $parser->tmp_to_core(1);

    #If someone includes a message, don't extract it
    $parser->extract_nested_messages(1);

    # Set up the prefix for files with auto-generated names:
    $parser->output_prefix("part");

    # If content length is <= 50000 bytes, store each msg as in-core scalar;
    # Else, write to a disk file (the default action):
    $parser->output_to_core(50000);

    ### Should we forgive normally-fatal errors?
    $parser->ignore_errors(1);
    $self->{'MIMEObj'} = eval { $parser->parse_data($content) };
    if ( my $error = $@ || $parser->last_error ) {
        $RT::Logger->error( "$error" );
        return ( 0, $error );
    }

    # Unfold all headers
    $self->{'MIMEObj'}->head->unfold;

    return ( 1, $self->loc("Template parsed") );

}

# }}}

# {{{ sub _ParseContent

# Perform Template substitutions on the template

sub _ParseContent {
    my $self = shift;
    my %args = (
        Argument       => undef,
        TicketObj      => undef,
        TransactionObj => undef,
        @_
    );

    my $content = $self->Content;
    unless ( defined $content ) {
        return ( undef, $self->loc("Permissions denied") );
    }

    # We need to untaint the content of the template, since we'll be working
    # with it
    $content =~ s/^(.*)$/$1/;
    my $template = Text::Template->new(
        type => 'STRING',
        SOURCE => $content
    );

    $args{'Ticket'} = delete $args{'TicketObj'} if $args{'TicketObj'};
    $args{'Transaction'} = delete $args{'TransactionObj'} if $args{'TransactionObj'};
    foreach my $key ( keys %args ) {
        next unless ref $args{ $key };
        next if ref $args{ $key } =~ /^(ARRAY|HASH|SCALAR|CODE)$/;
        my $val = $args{ $key };
        $args{ $key } = \$val;
    }

    $args{'Requestor'} = eval { $args{'Ticket'}->Requestors->UserMembersObj->first->Name };
    $args{'rtname'}    = RT->Config->Get('rtname');
    if ( $args{'Ticket'} ) {
        $args{'loc'} = sub { $args{'Ticket'}->loc(@_) };
    } else {
        $args{'loc'} = sub { $self->loc(@_) };
    }

    my $is_broken = 0;
    my $retval = $template->fill_in(
        HASH => \%args,
        BROKEN => sub {
            my (%args) = @_;
            $RT::Logger->error("Template parsing error: $args{error}")
                unless $args{error} =~ /^Died at /; # ignore intentional die()
            $is_broken++;
            return undef;
        }, 
    );
    return ( undef, $self->loc('Template parsing error') ) if $is_broken;

    # MIME::Parser has problems dealing with high-bit utf8 data.
    Encode::_utf8_off($retval);
    return ($retval);
}

# }}}

# {{{ sub current_user_has_queue_right

=head2 current_user_has_queue_right

Helper function to call the template's queue's current_user_has_queue_right with the passed in args.

=cut

sub current_user_has_queue_right {
    my $self = shift;
    return ( $self->QueueObj->current_user_has_right(@_) );
}

# }}}


sub QueueObj {
    my $self = shift;
    my $q = RT::Model::Queue->new($self->current_user);
    $q->load($self->__value('Queue'));
    return $q;
}
1;
