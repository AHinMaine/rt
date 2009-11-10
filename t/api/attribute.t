
use strict;
use warnings;
use RT::Test strict => 1; use Test::More; 
plan tests => 7;



my $user = RT->system_user;
my ($id, $msg) =  $user->user_object->add_attribute(name => 'SavedSearch', content => { query => 'Foo'} );
ok ($id, $msg);
my $attr = RT::Model::Attribute->new(current_user => RT->system_user);
$attr->load($id);
is($attr->name , 'SavedSearch');
$attr->set_sub_values( format => 'baz');

my $format = $attr->sub_value('format');
is ($format , 'baz');

$attr->set_sub_values( format => 'bar');
$format = $attr->sub_value('format');
is ($format , 'bar');

$attr->delete_all_sub_values();
$format = $attr->sub_value('format');
is ($format, undef);

$attr->set_sub_values(format => 'This is a format');

my $attr2 = RT::Model::Attribute->new(current_user => RT->system_user);
$attr2->load($id);
is ($attr2->sub_value('format'), 'This is a format');
$attr2->delete;
my $attr3 = RT::Model::Attribute->new(current_user => RT->system_user);
($id) = $attr3->load($id);
is ($id, 0);



1;
