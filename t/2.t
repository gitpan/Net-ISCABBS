#!/usr/bin/perl

use warnings;
use strict;

use Test::Simple tests => 4;

use Net::ISCABBS;

our $bbs = new Net::ISCABBS;
ok( defined $bbs );                 # check that we got something
ok( $bbs->isa('Net::ISCABBS') );    # and it's the right class
our %forums = $bbs->forums;
ok( scalar( keys(%forums) ) > 0 );    # See if we can see forums
ok( $bbs->logout );                   # Verify that we can log out
