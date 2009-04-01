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
use strict;
use warnings;

package RT::Model::User;

use base qw/RT::IsPrincipal::HasNoMembers RT::Record/;

=head1 NAME

RT::Model::User - RT User object

=head1 METHODS

=cut

use Digest::MD5;
use RT::Interface::Email;
use Encode;

use Jifty::DBI::Schema;

sub table {'Users'}

use Jifty::DBI::Record schema {
    column comments              => type is 'blob', default is '';
    column signature             => type is 'blob', default is '';
    column freeform_contact_info => type is 'blob', default is '';
    column
        organization =>,
        max_length is 200, type is 'varchar(200)', default is '';
    column
        real_name => max_length is 120,
        type is 'varchar(120)', default is '';
    column nickname => max_length is 16, type is 'varchar(16)', default is '';
    column lang     => max_length is 16, type is 'varchar(16)', default is '';
    column
        email_encoding => max_length is 16,
        type is 'varchar(16)', default is '';
    column
        web_encoding => max_length is 16,
        type is 'varchar(16)', default is '';
    column

        external_contact_info_id => max_length is 100,
        type is 'varchar(100)', default is '';
    column
        contact_info_system => max_length is 30,
        type is 'varchar(30)', default is '';
    column
        external_auth_id => max_length is 100,
        type is 'varchar(100)', default is '';
    column
        auth_system => max_length is 30,
        type is 'varchar(30)', default is '';
    column gecos => max_length is 16, type is 'varchar(16)', default is '';
    column
        home_phone => max_length is 30,
        type is 'varchar(30)', default is '';
    column
        work_phone => max_length is 30,
        type is 'varchar(30)', default is '';
    column
        mobile_phone => max_length is 30,
        type is 'varchar(30)', default is '';
    column
        pager_phone => max_length is 30,
        type is 'varchar(30)', default is '';
    column
        address1 => max_length is 200,
        type is 'varchar(200)', default is '';
    column
        address2 => max_length is 200,
        type is 'varchar(200)', default is '';
    column city     => max_length is 100, type is 'varchar(100)', default is '';
    column state    => max_length is 100, type is 'varchar(100)', default is '';
    column zip      => max_length is 16,  type is 'varchar(16)',  default is '';
    column country  => max_length is 50,  type is 'varchar(50)',  default is '';
    column time_zone => max_length is 50,  type is 'varchar(50)',  default is '';
    column pgp_key   => type is 'text';

};

use Jifty::Plugin::User::Mixin::Model::User;    # name, email, email_confirmed
use Jifty::Plugin::Authentication::Password::Mixin::Model::User;
use Jifty::Plugin::ActorMetadata::Mixin::Model::ActorMetadata map => {
    created_by => 'creator',
    created_on => 'created',
    updated_by => 'last_updated_by',
    updated_on => 'last_updated'
};

# XXX TODO, merging params should 'just work' but does not
__PACKAGE__->column('email')->writable(1);

sub set_email {
    my $self = shift;
    my $addr = shift;
    $self->__set( column => 'email', value => $addr );
}


=head2 create { PARAMHASH }



=cut

sub create {
    my $self = shift;
    my %args = (
        privileged          => 0,
        disabled            => 0,
        email               => '',
        email_confirmed     => 1,
        _record_transaction => 1,
        @_    # get the real argumentlist
    );

    # remove the value so it does not cripple SUPER::Create
    my $record_transaction = delete $args{'_record_transaction'};

    #Check the ACL
    Carp::confess unless ( $self->current_user );
    unless (
        $self->current_user->user_object->has_right(
            right  => 'AdminUsers',
            object => RT->system
        )
        )
    {
        return ( 0, _('No permission to create users') );
    }

    unless ( $self->canonicalize_user_info( \%args ) ) {
        return ( 0, _("Could not set user info") );
    }

    $args{'email'} = $self->canonicalize_email( $args{'email'} );

    # if the user doesn't have a name defined, set it to the email address
    $args{'name'} = $args{'email'} unless ( $args{'name'} );

    my $privileged = delete $args{'privileged'};

    if ( !$args{'password'} ) {
        $args{'password'} = '*NO-PASSWORD*';
    }

    elsif ( length( $args{'password'} ) < RT->config->get('MinimumPasswordLength') ) {
        return ( 0, _( "password needs to be at least %1 characters long", RT->config->get('MinimumPasswordLength') ) );
    }

    unless ( $args{'name'} ) {
        return ( 0, _("Must specify 'name' attribute") );
    }

    #SANITY CHECK THE name AND ABORT IF IT'S TAKEN
    if ( RT->system_user ) {    #This only works if RT->system_user has been defined
        my $TempUser = RT::Model::User->new( current_user => RT->system_user );
        $TempUser->load( $args{'name'} );
        return ( 0, _('name in use') ) if ( $TempUser->id );

        return ( 0, _('Email address in use') )
            unless ( $self->validate_email( $args{'email'} ) );
    } else {
        Jifty->log->warn("$self couldn't check for pre-existing users");
    }

    Jifty->handle->begin_transaction();

    # Groups deal with principal ids, rather than user ids.
    # When creating this user, set up a principal id for it.
    my $principal    = RT::Model::Principal->new( current_user => $self->current_user );
    my $principal_id = $principal->create(
        type => 'User',
        disabled       => $args{'disabled'},
    );

    # If we couldn't create a principal Id, get the fuck out.
    unless ($principal_id) {
        Jifty->handle->rollback();
        Jifty->log->fatal("Couldn't create a Principal on new user create.");
        Jifty->log->fatal("Strange things are afoot at the circle K");
        return ( 0, _('Could not create user') );
    }

    delete $args{'disabled'};

    $self->SUPER::create( id => $principal_id, %args );
    my $id = $self->id;

    #If the create failed.
    unless ($id) {
        Jifty->handle->rollback();
        Jifty->log->error( "Could not create a new user - " . join( '-', %args ) );

        return ( 0, _('Could not create user') );
    }

    my $aclstash = RT::Model::Group->new( current_user => $self->current_user );
    my $stash_id = $aclstash->create_acl_equivalence($principal);

    unless ($stash_id) {
        Jifty->handle->rollback();
        Jifty->log->fatal("Couldn't stash the user in groupmembers");
        return ( 0, _('Could not create user') );
    }

    my $everyone = RT::Model::Group->new( current_user => $self->current_user );
    $everyone->load_system_internal('Everyone');
    unless ( $everyone->id ) {
        Jifty->log->fatal("Could not load Everyone group on user creation.");
        Jifty->handle->rollback();
        return ( 0, _('Could not create user') );
    }

    my ( $everyone_id, $everyone_msg ) = $everyone->_add_member( principal => $self );
    unless ($everyone_id) {
        Jifty->log->fatal("Could not add user to Everyone group on user creation.");
        Jifty->log->fatal($everyone_msg);
        Jifty->handle->rollback();
        return ( 0, _('Could not create user') );
    }

    my $access_class = RT::Model::Group->new( current_user => $self->current_user );
    if ($privileged) {
        $access_class->load_system_internal('privileged');
    } else {
        $access_class->load_system_internal('Unprivileged');
    }

    unless ( $access_class->id ) {
        Jifty->log->fatal( "Could not load privileged or Unprivileged group on user creation" );
        Jifty->handle->rollback();
        return ( 0, _('Could not create user') );
    }

    my ( $ac_id, $ac_msg ) = $access_class->_add_member( principal => $self );

    unless ($ac_id) {
        Jifty->log->fatal( "Could not add user to privileged or Unprivileged group on user creation. aborted" );
        Jifty->log->fatal($ac_msg);
        Jifty->handle->rollback();
        return ( 0, _('Could not create user') );
    }

    if ($record_transaction) {
        $self->_new_transaction( type => "create" );
    }

    Jifty->handle->commit;

    return ( $id, _('User Created') );
}

=head2 set_privileged BOOL

If passed a true value, makes this user a member of the "privileged"  PseudoGroup.
Otherwise, makes this user a member of the "Unprivileged" pseudogroup. 

Returns a standard RT tuple of (val, msg);


=cut

sub set_privileged {
    my $self = shift;
    my $val  = shift;

    #Check the ACL
    unless (
        $self->current_user->has_right(
            right  => 'AdminUsers',
            object => RT->system
        )
        )
    {
        return ( 0, _('No permission to create users') );
    }
    my $priv = RT::Model::Group->new( current_user => $self->current_user );
    $priv->load_system_internal('privileged');

    unless ( $priv->id ) {
        Jifty->log->fatal("Could not find privileged pseudogroup");
        return ( 0, _("Failed to find 'privileged' users pseudogroup.") );
    }

    my $unpriv = RT::Model::Group->new( current_user => $self->current_user );
    $unpriv->load_system_internal('Unprivileged');
    unless ( $unpriv->id ) {
        Jifty->log->fatal("Could not find unprivileged pseudogroup");
        return ( 0, _("Failed to find 'Unprivileged' users pseudogroup") );
    }

    if ($val) {
        if ( $priv->has_member( principal =>  $self->principal ) ) {

            #Jifty->log->debug("That user is already privileged");
            return ( 0, _("That user is already privileged") );
        }
        if ( $unpriv->has_member( principal =>  $self->principal ) ) {
            $unpriv->_delete_member( $self->principal_id );
        } else {

            # if we had layered transactions, life would be good
            # sadly, we have to just go ahead, even if something
            # bogus happened
            Jifty->log->fatal( "User " . $self->id . " is neither privileged nor " . "unprivileged. something is drastically wrong." );
        }
        my ( $status, $msg ) = $priv->_add_member( principal => $self );
        if ($status) {
            return ( 1, _("That user is now privileged") );
        } else {
            return ( 0, $msg );
        }
    } else {
        if ( $unpriv->has_member( principal =>  $self->principal ) ) {

            #Jifty->log->debug("That user is already unprivileged");
            return ( 0, _("That user is already unprivileged") );
        }
        if ( $priv->has_member( principal =>  $self->principal ) ) {
            $priv->_delete_member( $self->principal_id );
        } else {

            # if we had layered transactions, life would be good
            # sadly, we have to just go ahead, even if something
            # bogus happened
            Jifty->log->fatal( "User " . $self->id . " is neither privileged nor " . "unprivileged. something is drastically wrong." );
        }
        my ( $status, $msg ) = $unpriv->_add_member( principal => $self );
        if ($status) {
            return ( 1, _("That user is now unprivileged") );
        } else {
            return ( 0, $msg );
        }
    }
}


=head2 privileged

Returns true if this user is privileged. Returns undef otherwise.

=cut

sub privileged {
    my $self = shift;
    my $priv = RT::Model::Group->new( current_user => $self->current_user );
    $priv->load_system_internal('privileged');
    if ( $priv->has_member( principal =>  $self->principal ) ) {
        return (1);
    } else {
        return (undef);
    }
}


# sub _bootstrap_create

#create a user without validating _any_ data.

#To be used only on database init.
# We can't localize here because it's before we _have_ a loc framework

sub _bootstrap_create {
    my $self = shift;
    my %args = (@_);

    Jifty->handle->begin_transaction();

    # Groups deal with principal ids, rather than user ids.
    # When creating this user, set up a principal id for it.
    my $principal = RT::Model::Principal->new( current_user => RT::CurrentUser->new( _bootstrap => 1 ) );
    my ( $principal_id, $pmsg ) = $principal->create(
        type => 'User',
        disabled       => '0'
    );

    # If we couldn't create a principal Id, get the fuck out.
    unless ($principal_id) {
        Jifty->handle->rollback();
        Jifty->log->fatal( "Couldn't create a Principal on new user create. Strange things are afoot at the circle K: $pmsg" );
        return ( 0, 'Could not create user' );
    }

    my ( $status, $user_msg ) = $self->SUPER::create(
# we need to feed creator and last_updated_by since current user doesn't have id yet
# and principal id *should* be the same as user id
            creator => $principal_id, 
            last_updated_by => $principal_id,
        id => $principal_id,
        %args, password => '*NO-PASSWORD*',
    );
    unless ($status) {
        die $user_msg;
    }
    my $id = $self->id;

    #If the create failed.
    unless ($id) {
        Jifty->handle->rollback();
        return ( 0, 'Could not create user' );    #never loc this
    }

    my $aclstash = RT::Model::Group->new( current_user => $self->current_user );

    my $stash_id = $aclstash->create_acl_equivalence($principal);

    unless ($stash_id) {
        Jifty->handle->rollback();
        Jifty->log->fatal("Couldn't stash the user in groupmembers");
        return ( 0, _('Could not create user') );
    }

    Jifty->handle->commit();

    return ( $id, 'User Created' );
}


sub delete {
    my $self = shift;

    return ( 0, _('Deleting this object would violate referential integrity') );

}

=head2 load

Load a user object from the database. Takes a single argument.
If the argument is numerical, load by the column 'id'. If a user
object or its subclass passed then loads the same user by id.
Otherwise, load by the "name" column which is the user's textual
username.

=cut

sub load {
    my $self = shift;
    my $identifier = shift || return undef;

    if ( $identifier !~ /\D/ ) {
        return $self->load_by_id($identifier);
    } elsif ( UNIVERSAL::isa( $identifier, 'RT::Model::User' ) ) {
        return $self->load_by_id( $identifier->id );
    } else {
        return $self->load_by_cols( "name", $identifier );
    }
}

=head2 load_by_email

Tries to load this user object from the database by the user's email address.


=cut

sub load_by_email {
    my $self    = shift;
    my $address = shift;

    # Never load an empty address as an email address.
    unless ($address) {
        return (undef);
    }

    $address = $self->canonicalize_email($address);

    #Jifty->log->debug("Trying to load an email address: $address");
    return $self->load_by_cols( "email", $address );
}

=head2 load_or_create_by_email ADDRESS

Attempts to find a user who has the provided email address. If that fails, creates an unprivileged user with
the provided email address and loads them. Address can be provided either as L<Email::Address> object
or string which is parsed using the module.

Returns a tuple of the user's id and a status message.
0 will be returned in place of the user's id in case of failure.

=cut

sub load_or_create_by_email {
    my $self  = shift;
    my $email = shift;

    my ( $message, $name );
    if ( UNIVERSAL::isa( $email => 'Email::Address' ) ) {
        ( $email, $name ) = ( $email->address, $email->phrase );
    } else {
        ( $email, $name ) = RT::Interface::Email::parse_address_from_header($email);
    }

    $self->load_by_email($email);
    $self->load($email) unless $self->id;
    $message = _('User loaded');

    unless ( $self->id ) {
        my $val;
        ( $val, $message ) = $self->create(
            name       => $email,
            email      => $email,
            real_name  => $name,
            privileged => 0,
            comments   => 'AutoCreated when added as a watcher',
        );
        unless ($val) {

            # Deal with the race condition of two account creations at once
            $self->load_by_email($email);
            unless ( $self->id ) {
                sleep 5;
                $self->load_by_email($email);
            }
            if ( $self->id ) {
                Jifty->log->error("Recovered from creation failure due to race condition");
                $message = _("User loaded");
            } else {
                Jifty->log->fatal( "Failed to create user " . $email . ": " . $message );
            }
        }
    }
    return ( 0, $message ) unless $self->id;
    return ( $self->id, $message );
}


=head2 validate_email ADDRESS

Returns true if the email address entered is not in use by another user or is 
undef or ''. Returns false if it's in use. 

=cut

sub validate_email {
    my $self  = shift;
    my $value = shift;

    # if the email address is null, it's always valid
    return (1) if ( !$value || $value eq "" );

    my $TempUser = RT::Model::User->new( current_user => RT->system_user );
    $TempUser->load_by_email($value);

    if ( $TempUser->id && ( !$self->id || $TempUser->id != $self->id ) ) {    # if we found a user with that address
                                                                              # it's invalid to set this user's address to it
        return (undef);
    } else {                                                                  #it's a valid email address
        return (1);
    }
}

=head2 email_frequency

Takes optional Ticket argument in paramhash. Returns 'no email',
'squelched', 'daily', 'weekly' or empty string depending on
user preferences.

=over 4

=item 'no email' - user has no email, so can not recieve notifications.

=item 'squelched' - returned only when Ticket argument is provided and
notifications to the user has been supressed for this ticket.

=item 'daily' - returned when user recieve daily messages digest instead
of immediate delivery.

=item 'weekly' - previous, but weekly.

=item empty string returned otherwise.

=back

=cut

sub email_frequency {
    my $self = shift;
    my %args = (
        ticket => undef,
        @_
    );
    return ''
      unless $self->id
          && $self->id != RT->nobody->id
          && $self->id != RT->system_user->id;
    return 'no email' unless my $email = $self->email;
    return 'squelched'
      if $args{'ticket'}
          && grep lc $email eq lc $_->content, $args{'ticket'}->squelch_mail_to;
    my $frequency = RT->config->get( 'EmailFrequency', $self ) || '';
    return 'daily'  if $frequency =~ /daily/i;
    return 'weekly' if $frequency =~ /weekly/i;
    return '';
}



=head2 canonicalize_email ADDRESS

canonicalize_email converts email addresses into canonical form.
it takes one email address in and returns the proper canonical
form. You can dump whatever your proper local config is in here.  Note
that it may be called as a static method; in this case the first argument
is class name not an object.

=cut

sub canonicalize_email {
    my $self  = shift;
    my $email = shift;

    # Example: the following rule would treat all email
    # coming from a subdomain as coming from second level domain
    # foo.com
    if (    my $match = RT->config->get('CanonicalizeEmailMatch')
        and my $replace = RT->config->get('CanonicalizeEmailReplace') )
    {
        $email =~ s/$match/$replace/gi;
    }
    return ($email);

}

=head2 canonicalize_user_info HASH of ARGS

canonicalize_UserInfo can convert all User->create options.

it takes a hashref of all the params sent to User->create and
returns that same hash, by default nothing is done.

This function is intended to allow users to have their info looked up via
an outside source and modified upon creation.

=cut

sub canonicalize_user_info {
    my $self    = shift;
    my $args    = shift;
    my $success = 1;

    return ($success);
}

=head2 Password and authentication related functions

=head3 set_random_password

Takes no arguments. Returns a status code and a new password or an error message.
If the status is 1, the second value returned is the new password.
If the status is anything else, the new value returned is the error code.

=cut

sub set_random_password {
    my $self = shift;

    unless ( $self->current_user_can_modify('password') ) {
        return ( 0, _("Permission Denied") );
    }

    my $min = (
          RT->config->get('MinimumPasswordLength') > 6
        ? RT->config->get('MinimumPasswordLength')
        : 6
    );
    my $max = (
          RT->config->get('MinimumPasswordLength') > 8
        ? RT->config->get('MinimumPasswordLength')
        : 8
    );
    my $pass = Text::Password::Pronounceable->generate( $min => $max );

    # If we have "notify user on

    my ( $val, $msg ) = $self->set_password($pass);

    #If we got an error return the error.
    return ( 0, $msg ) unless ($val);

    #Otherwise, we changed the password, lets return it.
    return ( 1, $pass );

}

=head3 set_password

Takes a string. Checks the string's length and sets this user's password 
to that string.

=cut

sub before_set_password {
    my $self     = shift;
    my $password = shift;

    unless ( $self->current_user_can_modify('password') ) {
        return ( 0, _('password: Permission Denied') );
    }

    if ( !$password ) {
        return ( 0, _("No password set") );
    } elsif ( length($password) < RT->config->get('MinimumPasswordLength') ) {
        return ( 0, _( "password needs to be at least %1 characters long", RT->config->get('MinimumPasswordLength') ) );
    }
    return ( 1, "ok" );

}

=head3 has_password
                                                                                
Returns true if the user has a valid password, otherwise returns false.         
                                                                               
=cut

sub has_password {
    my $self = shift;
    my $pwd  = $self->__value('password');
    return undef
        if !defined $pwd
            || $pwd eq ''
            || $pwd eq '*NO-PASSWORD*';

    return 1;
}

=head3 password_is

Checks if the user's password matches the provided I<PASSWORD>.

=cut

sub password_is {
    my $self = shift;
    my $pass = shift;

    return undef unless $self->__value('password');
    my ($hash, $salt) = @{$self->__value('password')};
    return 1 if ( $hash eq Digest::MD5::md5_hex($pass . $salt) );

    #  if it's a historical password we say ok.
    my $value = $self->__raw_value('password');

    my $md5 = Digest::MD5->new;
    $md5->add($pass);
    if (   $md5->hexdigest eq $value
        || $value eq crypt( $pass, $value )
        || $value eq $md5->b64digest )
    {
        $self->set_password($pass); # to update password in the new way
        return 1;
    }

    return undef;

}

=head3 generate_auth_token

Generate a random authentication string for the user.

=cut

sub generate_auth_token {
    my $self = shift;
    my $token = substr(Digest::MD5::md5_hex(time . {} . rand()),0,16);
    return $self->set_attribute( name => "AuthToken", content => $token );
}

=head3 generate_auth_string

Takes a string and returns back a hex hash string. Later you can use
this pair to make sure it's generated by this user using L</ValidateAuthString>

=cut

sub generate_auth_string {
    my $self = shift;
    my $protect = shift;

    my $str = $self->auth_token . $protect;
    utf8::encode($str);

    return substr(Digest::MD5::md5_hex($str),0,16);
}

=head3 validate_auth_string

Takes auth string and protected string. Returns true is protected string
has been protected by user's L</AuthToken>. See also L</GenerateAuthString>.

=cut

sub validate_auth_string {
    my $self = shift;
    my $auth_string = shift;
    my $protected = shift;

    my $str = $self->auth_token . $protected;
    utf8::encode( $str );

    return $auth_string eq substr(Digest::MD5::md5_hex($str),0,16);
}

=head2 set_disabled

Toggles the user's disabled flag.
If this flag is
set, all password checks for this user will fail. All ACL checks for this
user will fail. The user will appear in no user listings.

=cut 

sub set_disabled {
    my $self = shift;
    unless (
        $self->current_user->has_right(
            right  => 'AdminUsers',
            object => RT->system
        )
        )
    {
        return ( 0, _('Permission Denied') );
    }
    return $self->principal->set_disabled(@_);
}

=head2 has_group_right

Takes a paramhash which can contain
these items:
    GroupObj => RT::Model::Group or Group => integer
    right => 'right' 


Returns 1 if this user has the right specified in the paramhash for the Group
passed in.

Returns undef if they don't.

=cut

sub has_group_right {
    my $self = shift;
    my %args = (
        group_obj => undef,
        group     => undef,
        right     => undef,
        @_
    );

    if ( defined $args{'group'} ) {
        $args{'group_obj'} = RT::Model::Group->new( current_user => $self->current_user );
        $args{'group_obj'}->load( $args{'group'} );
    }

    # Validate and load up the group_id
    unless ( ( defined $args{'group_obj'} ) and ( $args{'group_obj'}->id ) ) {
        return undef;
    }

    # Figure out whether a user has the right we're asking about.
    my $retval = $self->has_right(
        object => $args{'group_obj'},
        right  => $args{'right'},
    );

    return ($retval);

}

=head2 own_groups

Returns a group collection object containing the groups of which this
user is a member.

=cut

sub own_groups {
    my $self   = shift;
    my $groups = RT::Model::GroupCollection->new( current_user => $self->current_user );
    $groups->limit_to_user_defined_groups;
    $groups->with_member(
        principal => $self->id,
        recursively  => 1
    );
    return $groups;
}


=head1 rights testing


=cut

=head2 has_right

Shim around principal_obj->has_right. See L<RT::Model::Principal>.

=cut

sub has_right {
    my $self = shift;
    return $self->principal->has_right(@_);

}

=head2 current_user_can_modify RIGHT

If the user has rights for this object, either because
he has 'AdminUsers' or (if he\'s trying to edit himself and the right isn\'t an 
admin right) 'ModifySelf', return 1. otherwise, return undef.

=cut

sub current_user_can_modify {
    my $self  = shift;
    my $right = shift;

    if ($self->current_user->has_right(
            right  => 'AdminUsers',
            object => RT->system
        )
        )
    {
        return (1);
    }

    #If the field is marked as an "administrators only" field,
    # don\'t let the user touch it.
    elsif (0) {    # $self->_accessible( $right, 'admin' ) ) {
        return (undef);
    }

    #If the current user is trying to modify themselves
    elsif (
        ( $self->id == $self->current_user->id )
        and (
            $self->current_user->has_right(
                right  => 'ModifySelf',
                object => RT->system
            )
        )
        )
    {
        return (1);
    }

    #If we don\'t have a good reason to grant them rights to modify
    # by now, they lose
    else {
        return (undef);
    }

}

=head2 current_user_has_right
  
Takes a single argument. returns 1 if $Self->current_user
has the requested right. returns undef otherwise

=cut

sub current_user_has_right {
    my $self  = shift;
    my $right = shift;
    return (
        $self->current_user->has_right(
            right  => $right,
            object => RT->system
        )
    );
}


sub _prefname {
    my $name = shift;
    if ( ref $name ) {
        $name = ref($name) . '-' . $name->id;
    }

    return 'Pref-' . $name;
}

=head2 preferences name/OBJ DEFAULT

Obtain user preferences associated with given object or name.
Returns DEFAULT if no preferences found.  If DEFAULT is a hashref,
override the entries with user preferences.

=cut

sub preferences {
    my $self    = shift;
    my $name    = _prefname(shift);
    my $default = shift;

    my $attr = RT::Model::Attribute->new( current_user => $self->current_user );
    $attr->load_by_name_and_object( object => $self, name => $name );

    my $content = $attr->id ? $attr->content : undef;
    unless ( ref $content eq 'HASH' ) {
        return defined $content ? $content : $default;
    }

    if ( ref $default eq 'HASH' ) {
        for ( keys %$default ) {
            exists $content->{$_} or $content->{$_} = $default->{$_};
        }
    } elsif ( defined $default ) {
        Jifty->log->error( "Preferences $name for user" . $self->id . " is hash but default is not" );
    }
    return $content;
}


=head2 set_preferences name/OBJ value

Set user preferences associated with given object or name.

=cut

sub set_preferences {
    my $self  = shift;
    my $name  = _prefname(shift);
    my $value = shift;

    return ( 0, _("No permission to set preferences") )
      unless $self->current_user_can_modify('Preferences');

    my $attr = RT::Model::Attribute->new( current_user => $self->current_user );
    $attr->load_by_name_and_object( object => $self, name => $name );
    if ( $attr->id ) {
        return $attr->set_content($value);
    } else {
        return $self->add_attribute( name => $name, content => $value );
    }
}

=head2 watched_queues ROLE_LIST

Returns a RT::Model::QueueCollection object containing every queue watched by the user.

Takes a list of roles which is some subset of ('cc', 'admin_cc').  Defaults to:

$user->watched_queues('cc', 'admin_cc');

=cut

sub watched_queues {

    my $self = shift;
    my @roles = @_ || ( 'cc', 'admin_cc' );

    my $watched_queues = RT::Model::QueueCollection->new( current_user => $self->current_user );

    my $group_alias = $watched_queues->join(
        alias1  => 'main',
        column1 => 'id',
        table2  => 'Groups',
        column2 => 'instance',
    );

    $watched_queues->limit(
        alias            => $group_alias,
        column           => 'domain',
        value            => 'RT::Model::Queue-Role',
        entry_aggregator => 'AND',
    );
    if ( grep { $_ eq 'cc' } @roles ) {
        $watched_queues->limit(
            subclause        => 'limit_ToWatchers',
            alias            => $group_alias,
            column           => 'type',
            value            => 'cc',
            entry_aggregator => 'OR',
        );
    }
    if ( grep { $_ eq 'admin_cc' } @roles ) {
        $watched_queues->limit(
            subclause        => 'limit_ToWatchers',
            alias            => $group_alias,
            column           => 'type',
            value            => 'admin_cc',
            entry_aggregator => 'OR',
        );
    }

    my $queues_alias = $watched_queues->join(
        alias1  => $group_alias,
        column1 => 'id',
        table2  => 'CachedGroupMembers',
        column2 => 'group_id',
    );
    $watched_queues->limit(
        alias  => $queues_alias,
        column => 'member_id',
        value  => $self->principal_id,
    );

    return $watched_queues;

}

sub _set {
    my $self = shift;

    my %args = (
        column             => undef,
        value              => undef,
        transaction_type   => 'set',
        record_transaction => 1,
        @_
    );

    # Nobody is allowed to futz with RT_System or Nobody

    if (   ( $self->id == RT->system_user->id )
        || ( $self->id == RT->nobody->id ) )
    {
        return ( 0, _("Can not modify system users") );
    }
    unless ( $self->current_user_can_modify( $args{'column'} ) ) {
        return ( 0, _("Permission Denied") );
    }

    my $Old = $self->SUPER::_value( $args{'column'} );

    my ( $ret, $msg ) = $self->SUPER::_set(
        column => $args{'column'},
        value  => $args{'value'}
    );

    #If we can't actually set the field to the value, don't record
    # a transaction. instead, get out of here.
    if ( $ret == 0 ) { return ( 0, $msg ); }

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
        return ( $ret, $msg );
    }
}

=head2 _value

Takes the name of a table column.
Returns its value as a string, if the user passes an ACL check

=cut

sub _value {

    my $self  = shift;
    my $field = shift;

    #If the current user doesn't have ACLs, don't let em at it.

    my %public_fields = map { $_ => 1 } qw( name email
        id organization disabled
        real_name nickname gecos ExternalAuthId
        auth_system ExternalContactInfoId
        ContactInfoSystem );

    #if the field is public, return it.

    if ( $public_fields{$field} ) {
        return ( $self->SUPER::_value($field) );

    }

    #If the user wants to see their own values, let them
    # TODO figure ouyt a better way to deal with this
    if (   $self->id
        && $self->current_user->id
        && $self->current_user->id == $self->id )
    {
        return ( $self->SUPER::_value($field) );
    }

    #If the user has the admin users right, return the field
    elsif (
        $self->current_user->user_object
        && $self->current_user->user_object->has_right(
            right  => 'AdminUsers',
            object => RT->system
        )
        )
    {
        return ( $self->SUPER::_value($field) );
    } else {
        return (undef);
    }

}

=head2 friendly_name

Return the friendly name

=cut

sub friendly_name {
    my $self = shift;
    return $self->real_name if $self->real_name;
    return $self->name      if $self->name;
    return "";
}

=head2 preferred_key

Returns the preferred key of the user. If none is set, then this will query
GPG and set the preferred key to the maximally trusted key found (and then
return it). Returns C<undef> if no preferred key can be found.

=cut

sub preferred_key {
    my $self = shift;
    return undef unless RT->config->get('GnuPG')->{'enable'};
    my $prefkey = $self->first_attribute('preferred_key');
    return $prefkey->content if $prefkey;

    # we don't have a preferred key for this user, so now we must query GPG
    require RT::Crypt::GnuPG;
    my %res = RT::Crypt::GnuPG::get_keys_for_encryption( $self->email );
    return undef unless defined $res{'info'};
    my @keys = @{ $res{'info'} };
    return undef if @keys == 0;

    if ( @keys == 1 ) {
        $prefkey = $keys[0]->{'fingerprint'};
    } else {

        # prefer the maximally trusted key
        @keys = sort { $b->{'trust_level'} <=> $a->{'trust_level'} } @keys;
        $prefkey = $keys[0]->{'fingerprint'};
    }

    $self->set_attribute( name => 'preferred_key', content => $prefkey );
    return $prefkey;
}

sub private_key {
    my $self = shift;

    my $key = $self->first_attribute('private_key') or return undef;
    return $key->content;
}

sub set_private_key {
    my $self = shift;
    my $key  = shift;

    # XXX: ACL
    unless ($key) {
        my ( $status, $msg ) = $self->delete_attribute('private_key');
        unless ($status) {
            Jifty->log->error("Couldn't delete attribute: $msg");
            return ( $status, _("Couldn't unset private key") );

        }
        return ( $status, _("Unset private key") );
    }

    # check that it's really private key
    {
        my %tmp = RT::Crypt::GnuPG::get_keys_for_signing($key);
        return ( 0, _("No such key or it's not suitable for signing") )
            if $tmp{'exit_code'} || !$tmp{'info'};
    }

    my ( $status, $msg ) = $self->set_attribute(
        name    => 'private_key',
        content => $key,
    );
    return ( $status, _("Couldn't set private key") )
        unless $status;
    return ( $status, _("Unset private key") );
}

sub basic_columns {
    ( [ name => 'User Id' ], [ email => 'Email' ], [ real_name => 'name' ], [ organization => 'organization' ], );

}

1;
