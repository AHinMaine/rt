# Any configuration directives you include  here will override 
# RT's default configuration file, RT_Config.pm
#
# To include a directive here, just copy the equivalent statement
# from RT_Config.pm and change the value. We've included a single
# sample value below.
#
# This file is actually a perl module, so you can include valid
# perl code, as well.
#
# The converse is also true, if this file isn't valid perl, you're
# going to run into trouble. To check your SiteConfig file, use
# this comamnd:
#
#   perl -c /path/to/your/etc/RT_SiteConfig.pm

Set(rtname => 'example.com');

# You must install Plugins on your own, this is only an example
# of the correct syntax to use when activating them.
# There should only be one set-Plugins declaration in your config file.
#SetArray(Plugins => (qw(RT::Extension::QuickDelete RT::FM)));

1;
