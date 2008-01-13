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
package RT::EmailParser;


use base qw/RT::Base/;

use strict;
use warnings;

use Mail::Address;
use MIME::Entity;
use MIME::Head;
use MIME::Parser;
use File::Temp qw/tempdir/;

=head1 name

  RT::EmailParser - helper functions for parsing parts from incoming
  email messages

=head1 SYNOPSIS


=head1 DESCRIPTION




=head1 METHODS

=head2 new

Returns a RT::EmailParser->new object

=cut

sub new  {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = {};
  bless ($self, $class);
  return $self;
}


=head2 SmartParseMIMEEntityFromScalar Message => SCALAR_REF [, Decode => BOOL, Exact => BOOL ] }

Parse a message stored in a scalar from scalar_ref.

=cut

sub SmartParseMIMEEntityFromScalar {
    my $self = shift;
    my %args = ( Message => undef, Decode => 1, Exact => 0, @_ );

    eval {
        my ( $fh, $temp_file );
        for ( 1 .. 10 ) {

            # on NFS and NTFS, it is possible that tempfile() conflicts
            # with other processes, causing a race condition. we try to
            # accommodate this by pausing and retrying.
            last
              if ( $fh, $temp_file ) =
              eval { File::Temp::tempfile( undef, UNLINK => 0 ) };
            sleep 1;
        }
        if ($fh) {

            #thank you, windows                      
            binmode $fh;
            $fh->autoflush(1);
            print $fh $args{'Message'};
            close($fh);
            if ( -f $temp_file ) {

                # We have to trust the temp file's name -- untaint it
                $temp_file =~ /(.*)/;
                my $entity = $self->ParseMIMEEntityFromFile( $1, $args{'Decode'}, $args{'Exact'} );
                unlink($1);
                return $entity;
            }
        }
    };

    #If for some reason we weren't able to parse the message using a temp file
    # try it with a scalar
    if ( $@ || !$self->Entity ) {
        return $self->ParseMIMEEntityFromScalar( $args{'Message'}, $args{'Decode'}, $args{'Exact'} );
    }

}


=head2 ParseMIMEEntityFromSTDIN

Parse a message from standard input

=cut

sub ParseMIMEEntityFromSTDIN {
    my $self = shift;
    return $self->ParseMIMEEntityFromFileHandle(\*STDIN, @_);
}

=head2 ParseMIMEEntityFromScalar  $message

Takes either a scalar or a reference to a scalar which contains a stringified MIME message.
Parses it.

Returns true if it wins.
Returns false if it loses.

=cut

sub ParseMIMEEntityFromScalar {
    my $self = shift;
    return $self->_ParseMIMEEntity( shift, 'parse_data', @_ );
}

=head2 ParseMIMEEntityFromFilehandle *FH

Parses a mime entity from a filehandle passed in as an argument

=cut

sub ParseMIMEEntityFromFileHandle {
    my $self = shift;
    return $self->_ParseMIMEEntity( shift, 'parse', @_ );
}

=head2 ParseMIMEEntityFromFile 

Parses a mime entity from a filename passed in as an argument

=cut

sub ParseMIMEEntityFromFile {
    my $self = shift;
    return $self->_ParseMIMEEntity( shift, 'parse_open', @_ );
}


sub _ParseMIMEEntity {
    my $self = shift;
    my $message = shift;
    my $method = shift;
    my $postprocess = (@_ ? shift : 1);
    my $exact = shift;

    # Create a new parser object:
    my $parser = MIME::Parser->new();
    $self->_SetupMIMEParser($parser);
    $parser->decode_bodies(0) if $exact;

    # TODO: XXX 3.0 we really need to wrap this in an eval { }
    unless ( $self->{'entity'} = $parser->$method($message) ) {
        $RT::Logger->crit("Couldn't parse MIME stream and extract the submessages");
        # Try again, this time without extracting nested messages
        $parser->extract_nested_messages(0);
        unless ( $self->{'entity'} = $parser->$method($message) ) {
            $RT::Logger->crit("couldn't parse MIME stream");
            return ( undef);
        }
    }

    $self->_PostProcessNewEntity if $postprocess;

    return $self->{'entity'};
}

sub _DecodeBodies {
    my $self = shift;
    return unless $self->{'entity'};
    
    my @parts = $self->{'entity'}->parts_DFS;
    $self->_DecodeBody($_) foreach @parts;
}

sub _DecodeBody {
    my $self = shift;
    my $entity = shift;

    my $old = $entity->bodyhandle or return;
    return unless $old->is_encoded;

    require MIME::Decoder;
    my $encoding = $entity->head->mime_encoding;
    my $decoder = new MIME::Decoder $encoding;
    unless ( $decoder ) {
        $RT::Logger->error("Couldn't find decoder for '$encoding', switching to binary");
        $old->is_encoded(0);
        return;
    }

    require MIME::Body;
    # XXX: use InCore for now, but later must switch to files
    my $new = new MIME::Body::InCore;
    $new->binmode(1);
    $new->is_encoded(0);

    my $source = $old->open('r') or die "couldn't open body: $!";
    my $destination = $new->open('w') or die "couldn't open body: $!";
    { 
        local $@;
        eval { $decoder->decode($source, $destination) };
        $RT::Logger->error($@) if $@;
    }
    $source->close or die "can't close: $!";
    $destination->close or die "can't close: $!";

    $entity->bodyhandle( $new );
}

=head2 _PostProcessNewEntity

cleans up and postprocesses a newly parsed MIME Entity

=cut

sub _PostProcessNewEntity {
    my $self = shift;

    #Now we've got a parsed mime object. 

    # Unfold headers that are have embedded newlines
    #  Better do this before conversion or it will break
    #  with multiline encoded Subject (RFC2047) (fsck.com #5594)
    $self->Head->unfold;

    # try to convert text parts into utf-8 charset
    RT::I18N::set_mime_entity_to_encoding($self->{'entity'}, 'utf-8');
}

=head2 ParseCcAddressesFromHead HASHREF

Takes a hashref object containing QueueObj, Head and CurrentUser objects.
Returns a list of all email addresses in the To and Cc 
headers b<except> the current Queue\'s email addresses, the CurrentUser\'s 
email address and anything that the RT->Config->Get('RTAddressRegexp') matches.

=cut

sub ParseCcAddressesFromHead {

    my $self = shift;

    my %args = (
        QueueObj    => undef,
        CurrentUser => undef,
        @_
    );

    my (@Addresses);

    my @ToObjs = Mail::Address->parse( $self->Head->get('To') );
    my @CcObjs = Mail::Address->parse( $self->Head->get('Cc') );

    foreach my $AddrObj ( @ToObjs, @CcObjs ) {
        my $Address = $AddrObj->address;
        my $user = RT::Model::User->new(current_user => RT->system_user);
        $Address = $user->canonicalize_email($Address);
        next if ( lc $args{'CurrentUser'}->email   eq lc $Address );
        next if ( lc $args{'QueueObj'}->correspond_address eq lc $Address );
        next if ( lc $args{'QueueObj'}->comment_address    eq lc $Address );
        next if ( $self->IsRTAddress($Address) );

        push ( @Addresses, $Address );
    }
    return (@Addresses);
}



=head2 ParseSenderAddressFromHead

Takes a MIME::Header object. Returns a tuple: (user@host, friendly name) 
of the From (evaluated in order of Reply-To:, From:, Sender)

=cut

sub ParseSenderAddressFromHead {
    my $self = shift;

    #Figure out who's sending this message.
    my $From = $self->Head->get('Reply-To')
      || $self->Head->get('From')
      || $self->Head->get('Sender');
    return ( $self->ParseAddressFromHeader($From) );
}



=head2 ParseErrorsToAddressFromHead

Takes a MIME::Header object. Return a single value : user@host
of the From (evaluated in order of Errors-To:,Reply-To:, From:, Sender)

=cut

sub ParseErrorsToAddressFromHead {
    my $self = shift;

    #Figure out who's sending this message.

    foreach my $header ( 'Errors-To', 'Reply-To', 'From', 'Sender' ) {

        # If there's a header of that name
        my $headerobj = $self->Head->get($header);
        if ($headerobj) {
            my ( $addr, $name ) = $self->ParseAddressFromHeader($headerobj);

            # If it's got actual useful content...
            return ($addr) if ($addr);
        }
    }
}



=head2 ParseAddressFromHeader ADDRESS

Takes an address from $self->Head->get('Line') and returns a tuple: user@host, friendly name

=cut

sub ParseAddressFromHeader {
    my $self = shift;
    my $Addr = shift;

    # Perl 5.8.0 breaks when doing regex matches on utf8
    Encode::_utf8_off($Addr) if $] == 5.008;
    my @Addresses = Mail::Address->parse($Addr);

    my $AddrObj = $Addresses[0];

    unless ( ref($AddrObj) ) {
        return ( undef, undef );
    }

    my $name = ( $AddrObj->phrase || $AddrObj->comment || $AddrObj->address );

    #Lets take the from and load a user object.
    my $Address = $AddrObj->address;

    return ( $Address, $name );
}



=head2 IsRTaddress ADDRESS

Takes a single parameter, an email address. 
Returns true if that address matches the C<RTAddressRegexp> config option.
Returns false, otherwise.


=cut

sub IsRTAddress {
    my $self = shift;
    my $address = shift;

    # Example: the following rule would tell RT not to Cc 
    #   "tickets@noc.example.com"
    my $address_re = RT->Config->Get('RTAddressRegexp');
    if ( defined $address_re && $address =~ /$address_re/i ) {
        return 1;
    }
    return undef;
}




=head2 CullRTAddresses ARRAY

Takes a single argument, an array of email addresses.
Returns the same array with any IsRTAddress()es weeded out.


=cut

sub CullRTAddresses {
    my $self = shift;
    my @addresses= (@_);
    my @addrlist;

    foreach my $addr( @addresses ) {
                                 # We use the class instead of the instance
                                 # because sloppy code calls this method
                                 # without a $self
      push (@addrlist, $addr)    unless RT::EmailParser->IsRTAddress($addr);
    }
    return (@addrlist);
}





# LookupExternalUserInfo is a site-definable method for synchronizing
# incoming users with an external data source. 
#
# This routine takes a tuple of email and friendly_name
#   email is the user's email address, ususally taken from
#       an email message's From: header.
#   friendly_name is a freeform string, ususally taken from the "comment" 
#       portion of an email message's From: header.
#
# If you define an AutoRejectRequest template, RT will use this   
# template for the rejection message.


=head2 LookupExternalUserInfo

 LookupExternalUserInfo is a site-definable method for synchronizing
 incoming users with an external data source. 

 This routine takes a tuple of email and friendly_name
    email is the user's email address, ususally taken from
        an email message's From: header.
    friendly_name is a freeform string, ususally taken from the "comment" 
        portion of an email message's From: header.

 It returns (FoundInExternalDatabase, ParamHash);

   FoundInExternalDatabase must  be set to 1 before return if the user 
   was found in the external database.

   ParamHash is a Perl parameter hash which can contain at least the 
   following fields. These fields are used to populate RT's users 
   database when the user is created.

    email is the email address that RT should use for this user.  
    name is the 'name' attribute RT should use for this user. 
         'name' is used for things like access control and user lookups.
    real_name is what RT should display as the user's name when displaying 
         'friendly' names

=cut

sub LookupExternalUserInfo {
  my $self = shift;
  my $email = shift;
  my $real_name = shift;

  my $FoundInExternalDatabase = 1;
  my %params;

  #name is the RT username you want to use for this user.
  $params{'name'} = $email;
  $params{'email'} = $email;
  $params{'real_name'} = $real_name;

  # See RT's contributed code for examples.
  # http://www.fsck.com/pub/rt/contrib/
  return ($FoundInExternalDatabase, %params);
}

=head2 Head

Return the parsed head from this message

=cut

sub Head {
    my $self = shift;
    return $self->Entity->head;
}

=head2 Entity 

Return the parsed Entity from this message

=cut

sub Entity {
    my $self = shift;
    return $self->{'entity'};
}



=head2 _SetupMIMEParser $parser

A private instance method which sets up a mime parser to do its job

=cut


    ## TODO: Does it make sense storing to disk at all?  After all, we
    ## need to put each msg as an in-core scalar before saving it to
    ## the database, don't we?

    ## At the same time, we should make sure that we nuke attachments 
    ## Over max size and return them

sub _SetupMIMEParser {
    my $self   = shift;
    my $parser = shift;
    
    # Set up output directory for files:

    my $tmpdir = File::Temp::tempdir( TMPDIR => 1, CLEANUP => 1 );
    push ( @{ $self->{'AttachmentDirs'} }, $tmpdir );
    $parser->output_dir($tmpdir);
    $parser->filer->ignore_filename(1);

    #If someone includes a message, extract it
    $parser->extract_nested_messages(1);

    $parser->extract_uuencode(1);    ### default is false

    # Set up the prefix for files with auto-generated names:
    $parser->output_prefix("part");

    # do _not_ store each msg as in-core scalar;

    $parser->output_to_core(0);

    # From the MIME::Parser docs:
    # "Normally, tmpfiles are created when needed during parsing, and destroyed automatically when they go out of scope"
    # Turns out that the default is to recycle tempfiles
    # Temp files should never be recycled, especially when running under perl taint checking
    
    $parser->tmp_recycling(0) if $parser->can('tmp_recycling');

}


sub DESTROY {
    my $self = shift;
    File::Path::rmtree([@{$self->{'AttachmentDirs'}}],0,1);
}



eval "require RT::EmailParser_Vendor";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/EmailParser_Vendor.pm});
eval "require RT::EmailParser_Local";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/EmailParser_Local.pm});

1;
