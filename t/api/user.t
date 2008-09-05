
use strict;
use warnings;
use RT::Test; use Test::More; 
plan tests => 104;
use RT;



{

ok(require RT::Model::User);

}

{

# Make sure we can create a user

my $u1 = RT::Model::User->new(current_user => RT->system_user);
is(ref($u1), 'RT::Model::User');
my ($id, $msg) = $u1->create(name => 'CreateTest1'.$$, email => $$.'create-test-1@example.com');
ok ($id, "Creating user CreateTest1 - " . $msg );

# Make sure we can't create a second user with the same name
my $u2 = RT::Model::User->new(current_user => RT->system_user);
($id, $msg) = $u2->create(name => 'CreateTest1'.$$, email => $$.'create-test-2@example.com');
ok (!$id, $msg);


# Make sure we can't create a second user with the same email address
my $u3 = RT::Model::User->new(current_user => RT->system_user);
($id, $msg) = $u3->create(name => 'CreateTest2'.$$, email => $$.'create-test-1@example.com');
ok (!$id, $msg);

# Make sure we can create a user with no email address
my $u4 = RT::Model::User->new(current_user => RT->system_user);
($id, $msg) = $u4->create(name => 'CreateTest3'.$$);
ok ($id, $msg);

# make sure we can create a second user with no email address
my $u5 = RT::Model::User->new(current_user => RT->system_user);
($id, $msg) = $u5->create(name => 'CreateTest4'.$$);
ok ($id, $msg);

# make sure we can create a user with a blank email address
my $u6 = RT::Model::User->new(current_user => RT->system_user);
($id, $msg) = $u6->create(name => 'CreateTest6'.$$, email => '');
ok ($id, $msg);
# make sure we can create a second user with a blankemail address
my $u7 = RT::Model::User->new(current_user => RT->system_user);
($id, $msg) = $u7->create(name => 'CreateTest7'.$$, email => '');
ok ($id, $msg);

# Can we change the email address away from from "";
($id,$msg) = $u7->set_email('foo@bar'.$$);
ok ($id, $msg);
TODO: { 
    local $TODO = "XXX TODO RT4 - jifty::plugin::user doesn't let you change email addresses. that's busted";
# can we change the address back to "";  
($id,$msg) = $u7->set_email('');
ok ($id, $msg);
is ($u7->email, '');


}
}

{


ok(my $user = RT::Model::User->new(current_user => RT->system_user));
ok($user->load('root'), "Loaded user 'root'");
ok($user->privileged, "User 'root' is privileged");
ok(my ($v,$m) = $user->set_privileged(0));
is ($v ,1, "Set unprivileged suceeded ($m)");

ok(!$user->privileged, "User 'root' is no longer privileged");
ok(my ($v2,$m2) = $user->set_privileged(1));
is ($v2 ,1, "Set privileged suceeded ($m2");
ok($user->privileged, "User 'root' is privileged again");


}

{

ok(my $u = RT::Model::User->new(current_user => RT->system_user));
ok($u->load(1), "Loaded the first user");
is($u->principal->type, 'User' , "Principal 1 is a user, not a group");


}

{

my $root = RT::Model::User->new(current_user => RT->system_user);
$root->load('root');
ok($root->id, "Found the root user");
my $rootq = RT::Model::Queue->new(current_user => RT::CurrentUser->new( id => $root->id));
$rootq->load(1);
ok($rootq->id, "Loaded the first queue");

ok ($rootq->current_user->has_right(right=> 'CreateTicket', object => $rootq), "Root can create tickets");

my $new_user = RT::Model::User->new(current_user => RT->system_user);
my ($id, $msg) = $new_user->create(name => 'ACLTest'.$$);

ok ($id, "Created a new user for acl test $msg");

my $q = RT::Model::Queue->new( current_user => RT::CurrentUser->new( id => $new_user->id));
$q->load(1);
ok($q->id, "Loaded the first queue");


ok (!$q->current_user->has_right(right => 'CreateTicket', object => $q), "Some random user doesn't have the right to create tickets");
ok (my ($gval, $gmsg) = $new_user->principal->grant_right( right => 'CreateTicket', object => $q), "Granted the random user the right to create tickets");
ok ($gval, "Grant succeeded - $gmsg");


ok ($q->current_user->has_right(right => 'CreateTicket', object => $q), "The user can create tickets after we grant him the right");
ok ( ($gval, $gmsg) = $new_user->principal->revoke_right( right => 'CreateTicket', object => $q), "revoked the random user the right to create tickets");
ok ($gval, "Revocation succeeded - $gmsg");
ok (!$q->current_user->has_right(right => 'CreateTicket', object => $q), "The user can't create tickets anymore");





# Create a ticket in the queue
my $new_tick = RT::Model::Ticket->new(current_user => RT->system_user);
my ($tickid, $tickmsg) = $new_tick->create(subject=> 'ACL Test', queue => 'General');
ok($tickid, "Created ticket: $tickid");
# Make sure the user doesn't have the right to modify tickets in the queue
ok (!$new_user->has_right( object => $new_tick, right => 'ModifyTicket'), "User can't modify the ticket without group membership");
# Create a new group
my $group = RT::Model::Group->new(current_user => RT->system_user);
$group->create_user_defined_group(name => 'ACLTest'.$$);
ok($group->id, "Created a new group Ok");
# Grant a group the right to modify tickets in a queue
ok(my ($gv,$gm) = $group->principal->grant_right( object => $q, right => 'ModifyTicket'),"Granted the group the right to modify tickets");
ok($gv,"Grant succeeed - $gm");
# Add the user to the group
ok( my ($aid, $amsg) = $group->add_member($new_user->principal_id), "Added the member to the group");
ok ($aid, "Member added to group: $amsg");
# Make sure the user does have the right to modify tickets in the queue
ok ($new_user->has_right( object => $new_tick, right => 'ModifyTicket'), "User can modify the ticket with group membership");


# Remove the user from the group
ok( my ($did, $dmsg) = $group->delete_member($new_user->principal_id), "Deleted the member from the group");
ok ($did,"Deleted the group member: $dmsg");
# Make sure the user doesn't have the right to modify tickets in the queue
ok (!$new_user->has_right( object => $new_tick, right => 'ModifyTicket'), "User can't modify the ticket without group membership");


my $q_as_system = RT::Model::Queue->new(current_user => RT->system_user);
$q_as_system->load(1);
ok($q_as_system->id, "Loaded the first queue");

# Create a ticket in the queue
my $new_tick2 = RT::Model::Ticket->new(current_user => RT->system_user);
(my $tick2id, $tickmsg) = $new_tick2->create(subject=> 'ACL Test 2', queue =>$q_as_system->id);
ok($tick2id, "Created ticket: $tick2id");
is($new_tick2->queue->id, $q_as_system->id, "Created a new ticket in queue 1");


# make sure that the user can't do this without subgroup membership
ok (!$new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can't modify the ticket without group membership");

# Create a subgroup
my $subgroup = RT::Model::Group->new(current_user => RT->system_user);
$subgroup->create_user_defined_group(name => 'Subgrouptest'.$$);
ok($subgroup->id, "Created a new group ".$subgroup->id."Ok");
#Add the subgroup as a subgroup of the group
my ($said, $samsg) =  $group->add_member($subgroup->principal_id);
ok ($said, "Added the subgroup as a member of the group");
# Add the user to a subgroup of the group

my ($usaid, $usamsg) =  $subgroup->add_member($new_user->principal_id);
ok($usaid,"Added the user ".$new_user->id."to the subgroup");
# Make sure the user does have the right to modify tickets in the queue
ok ($new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can modify the ticket with subgroup membership");

#  {{{ Deal with making sure that members of subgroups of a disabled group don't have rights

($id, $msg) =  $group->set_disabled(1);
ok ($id,$msg);
ok (!$new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can't modify the ticket when the group ".$group->id. " is disabled");
 ($id, $msg) =  $group->set_disabled(0);
ok($id,$msg);
# Test what happens when we disable the group the user is a member of directly

($id, $msg) =  $subgroup->set_disabled(1);
 ok ($id,$msg);
ok (!$new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can't modify the ticket when the group ".$subgroup->id. " is disabled");
 ($id, $msg) =  $subgroup->set_disabled(0);
 ok ($id,$msg);
ok ($new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can modify the ticket without group membership");

# }}}


my ($usrid, $usrmsg) =  $subgroup->delete_member($new_user->principal_id);
ok($usrid,"removed the user from the group - $usrmsg");
# Make sure the user doesn't have the right to modify tickets in the queue
ok (!$new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can't modify the ticket without group membership");

#revoke the right to modify tickets in a queue
ok(($gv,$gm) = $group->principal->revoke_right( object => $q, right => 'ModifyTicket'),"Granted the group the right to modify tickets");
ok($gv,"revoke succeeed - $gm");

# {{{ Test the user's right to modify a ticket as a _queue_ admincc for a Right granted at the _queue_ level

# Grant queue admin cc the right to modify ticket in the queue 
ok(my ($qv,$qm) = $q_as_system->role_group("admin_cc")->principal->grant_right( object => $q_as_system, right => 'ModifyTicket'),"Granted the queue adminccs the right to modify tickets");
ok($qv, "Granted the right successfully - $qm");

# Add the user as a queue admincc
ok (my ($add_id, $add_msg) = $q_as_system->add_watcher(type => 'admin_cc', principal_id => $new_user->principal_id)  , "Added the new user as a queue admincc");
ok ($add_id, "the user is now a queue admincc - $add_msg");

# Make sure the user does have the right to modify tickets in the queue
ok ($new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can modify the ticket as an admincc");
# Remove the user from the role  group
ok (my ($del_id, $del_msg) = $q_as_system->delete_watcher(type => 'admin_cc', principal_id => $new_user->principal_id)  , "Deleted the new user as a queue admincc");

# Make sure the user doesn't have the right to modify tickets in the queue
ok (!$new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can't modify the ticket without group membership");

# }}}

# {{{ Test the user's right to modify a ticket as a _ticket_ admincc with the Right granted at the _queue_ level

# Add the user as a ticket admincc
ok (my( $uadd_id, $uadd_msg) = $new_tick2->add_watcher(type => 'admin_cc', principal_id => $new_user->principal_id)  , "Added the new user as a queue admincc");
ok ($add_id, "the user is now a queue admincc - $add_msg");

# Make sure the user does have the right to modify tickets in the queue
ok ($new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can modify the ticket as an admincc");

# Remove the user from the role  group
ok (( $del_id, $del_msg) = $new_tick2->delete_watcher(type => 'admin_cc', principal_id => $new_user->principal_id)  , "Deleted the new user as a queue admincc");

# Make sure the user doesn't have the right to modify tickets in the queue
ok (!$new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can't modify the ticket without group membership");


# Revoke the right to modify ticket in the queue 
ok(my ($rqv,$rqm) = $q_as_system->role_group("admin_cc")->principal->revoke_right( object => $q_as_system, right => 'ModifyTicket'),"Revokeed the queue adminccs the right to modify tickets");
ok($rqv, "Revoked the right successfully - $rqm");

# }}}



# {{{ Test the user's right to modify a ticket as a _queue_ admincc for a Right granted at the _system_ level

# Before we start Make sure the user does not have the right to modify tickets in the queue
ok (!$new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can not modify the ticket without it being granted");
ok (!$new_user->has_right( object => $new_tick2->queue, right => 'ModifyTicket'), "User can not modify tickets in the queue without it being granted");

# Grant queue admin cc the right to modify ticket in the queue 
ok(($qv,$qm) = $q_as_system->role_group("admin_cc")->principal->grant_right( object => RT->system, right => 'ModifyTicket'),"Granted the queue adminccs the right to modify tickets");
ok($qv, "Granted the right successfully - $qm");

# Make sure the user can't modify the ticket before they're added as a watcher
ok (!$new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can not modify the ticket without being an admincc");
ok (!$new_user->has_right( object => $new_tick2->queue, right => 'ModifyTicket'), "User can not modify tickets in the queue without being an admincc");

# Add the user as a queue admincc
ok (($add_id, $add_msg) = $q_as_system->add_watcher(type => 'admin_cc', principal_id => $new_user->principal_id)  , "Added the new user as a queue admincc");
ok ($add_id, "the user is now a queue admincc - $add_msg");

# Make sure the user does have the right to modify tickets in the queue
ok ($new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can modify the ticket as an admincc");
ok ($new_user->has_right( object => $new_tick2->queue, right => 'ModifyTicket'), "User can modify tickets in the queue as an admincc");
# Remove the user from the role  group
ok (($del_id, $del_msg) = $q_as_system->delete_watcher(type => 'admin_cc', principal_id => $new_user->principal_id)  , "Deleted the new user as a queue admincc");

# Make sure the user doesn't have the right to modify tickets in the queue
ok (!$new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can't modify the ticket without group membership");
ok (!$new_user->has_right( object => $new_tick2->queue, right => 'ModifyTicket'), "User can't modify tickets in the queue without group membership");

# }}}

# {{{ Test the user's right to modify a ticket as a _ticket_ admincc with the Right granted at the _queue_ level

ok (!$new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can not modify the ticket without being an admincc");
ok (!$new_user->has_right( object => $new_tick2->queue, right => 'ModifyTicket'), "User can not modify tickets in the queue obj without being an admincc");


# Add the user as a ticket admincc
ok ( ($uadd_id, $uadd_msg) = $new_tick2->add_watcher(type => 'admin_cc', principal_id => $new_user->principal_id)  , "Added the new user as a queue admincc");
ok ($add_id, "the user is now a queue admincc - $add_msg");

# Make sure the user does have the right to modify tickets in the queue
ok ($new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can modify the ticket as an admincc");
ok (!$new_user->has_right( object => $new_tick2->queue, right => 'ModifyTicket'), "User can not modify tickets in the queue obj being only a ticket admincc");

# Remove the user from the role  group
ok ( ($del_id, $del_msg) = $new_tick2->delete_watcher(type => 'admin_cc', principal_id => $new_user->principal_id)  , "Deleted the new user as a queue admincc");

# Make sure the user doesn't have the right to modify tickets in the queue
ok (!$new_user->has_right( object => $new_tick2, right => 'ModifyTicket'), "User can't modify the ticket without being an admincc");
ok (!$new_user->has_right( object => $new_tick2->queue, right => 'ModifyTicket'), "User can not modify tickets in the queue obj without being an admincc");


# Revoke the right to modify ticket in the queue 
ok(($rqv,$rqm) = $q_as_system->role_group("admin_cc")->principal->revoke_right( object => RT->system, right => 'ModifyTicket'),"Revokeed the queue adminccs the right to modify tickets");
ok($rqv, "Revoked the right successfully - $rqm");

# }}}




# Grant "privileged users" the system right to create users
# Create a privileged user.
# have that user create another user
# Revoke the right for privileged users to create users
# have the privileged user try to create another user and fail the ACL check


}

1;
