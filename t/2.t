#!/usr/bin/perl

use warnings;
use strict;

use Test::Simple tests => 7;

use Net::ISCABBS;

our $bbs = new Net::ISCABBS;
ok( defined $bbs );                 # check that we got something
ok( $bbs->isa('Net::ISCABBS') );    # and it is the right class
our %forums = $bbs->forums;
ok( scalar( keys(%forums) ) > 0 );    # See if we can see forums
my $lobby;
ok( $lobby = $bbs->jump(0) );         # Everyone should be able to jump
                                      # to the lobby.
ok( $lobby->{lastnote} > 0 );         # The newest post in the lobby
                                      # should have a reasonable number
ok( my $post = $bbs->read( message => $lobby->{lastnote} ) );

# Read the newest Lobby> post

ok( $bbs->logout );                   # Verify that we can log out
