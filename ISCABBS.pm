package Net::ISCABBS;
$VERSION = 0.51;
require IO::Socket::INET;
use strict;
use warnings;

# Subversion ID $Id: ISCABBS.pm 40 2004-12-03 22:26:34Z minter $

sub new
{
    my ( $class, %arg ) = @_;

    my $host = $arg{host} || "bbs.isca.uiowa.edu";
    my $port = $arg{port} || "6145";
    my $login    = $arg{login};
    my $password = $arg{password};
    my $loggedin = 0;

    my $socket = IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port,
        Proto    => "tcp",
        Type     => IO::Socket::INET::SOCK_STREAM()
      )
      or return 0;

    my $welcome = <$socket>;
    return 0 unless ( $welcome =~ /^2/ );

    if ( $login && $password )
    {
        print $socket "LOGIN $login\t$password\n";
        my $answer = <$socket>;
        if ( $answer =~ /^2/ )
        {
            $loggedin = 1;
        }
        else
        {
            return 0;
        }
    }

    bless {
        _host     => $host,
        _port     => $port,
        _socket   => $socket,
        _loggedin => $loggedin,
    }, $class;
}

sub forums
{
    my $self   = shift;
    my $type   = shift || "all";
    my $socket = $self->{_socket};
    my %forums = ();
    print $socket "LIST $type\n";
    my $status = <$socket>;
    if ( $status =~ /^3/ )
    {

        while ( my $line = <$socket> )
        {
            chomp($line);

            last if ( $line =~ /^\.$/ );
            my @tuples = split( /\t/, $line );
            my %topichash;
            foreach my $pair (@tuples)
            {
                my ( $key, $value ) = split( /:/, $pair );
                $topichash{$key} = $value;
            }
            my $topicid = $topichash{topic};
            $forums{$topicid} = \%topichash;
        }
    }
    return %forums;
}

sub jump
{
    my $self  = shift;
    my $forum = $_[0];

    my $socket = $self->{_socket};

    print $socket "TOPIC $forum\n";
    my $response = <$socket>;
    if ( $response =~ /^2/ )
    {
        my $forumdata = {};

        $response =~ s/^.*?\t//;
        my @tuples = split( /\t/, $response );
        foreach my $pair (@tuples)
        {
            my ( $key, $value ) = split( /:/, $pair );
            if ( $key eq "admin" )
            {
                my ( $id, $name, $hidden ) = split( /\//, $value );
                $value = $name;
            }
            $forumdata->{$key} = $value;
        }

        $self->{_forum}     = $forumdata->{topic};
        $self->{_lastnote}  = $forumdata->{lastnote};
        $self->{_firstnote} = $forumdata->{firstnote};

        return $forumdata;

    }
    else
    {
        return 0;
    }
}

sub get_first_unread
{
    my $self   = shift;
    my $socket = $self->{_socket};

    print $socket "SHOW rcval\n";
    chomp( my $response = <$socket> );
    if ( $response =~ /^2.*?\t(\d+)$/ )
    {
        return $1;
    }
    else
    {
        return 0;
    }

}

sub read
{
    my $self   = shift;
    my $socket = $self->{_socket};
    my $start  = shift || $self->get_first_unread;
    if ( $start > $self->{_lastnote} )
    {
        return undef;
    }
    else
    {
        my $nextmessage = $start + 1;
        print $socket "READ $start\n";
        chomp( my $response = <$socket> );
        if ( $response =~ /^3/ )
        {
            my %message;
            while (1)
            {

                # Get header info until we hit a blank line
                chomp( my $headerline = <$socket> );
                last if ( $headerline =~ /^$/ );
                my ( $key, $value ) = split( /:\s+/, $headerline );
                $key = lc($key);
                $key = "author" if ( $key eq "from" );
                next if ( $key eq "formal-name" );
                $message{$key} = $value;
            }

            my @lines;

            while ( chomp( $response = <$socket> ) )
            {
                last if ( $response =~ /^\.$/ );
                push( @lines, $response );
            }
            my $body = join( "\n", @lines );

            $message{body} = $body;
            print $socket "SETRC $nextmessage\n";
            chomp( $response = <$socket> );

            return \%message;
        }
        else
        {
            return 0;
        }
    }

}

sub get_forum_headers
{
    my %xhdr;
    my $self   = shift;
    my $socket = $self->{_socket};
    return 0 unless defined $self->{_forum};

    print $socket "XHDR ALL\n";
    my $result = <$socket>;
    return 0 unless ( $result =~ /^3/ );

    while ( my $noteinfo = <$socket> )
    {
        last if ( $noteinfo =~ /^\./ );
        my $notenum;
        my %tmphash;
        chomp($noteinfo);
        my @tuples = split( /\t/, $noteinfo );
        foreach my $tuple (@tuples)
        {
            my ( $key, $value ) = split( /:/, $tuple );
            if ( $key eq "noteno" )
            {
                $notenum = $value;
            }
            elsif ( $key eq "formal-author" )
            {
                my ( undef, $author, undef ) = split( /\//, $value );
                $tmphash{author} = $author;
            }
            else
            {
                $tmphash{$key} = $value;
            }
        }
        $xhdr{$notenum} = \%tmphash;
    }
    return %xhdr;
}

sub set_firstunread
{
    my $self      = shift;
    my $socket    = $self->{_socket};
    my $messageid = shift or return 0;

    if (   ( $messageid >= $self->{_firstnote} )
        && ( $messageid <= $self->{_lastnote} ) )
    {
        print $socket "SETRC $messageid\n";
        return 1;
    }
    else
    {
        return 0;
    }
}

sub forums_with_unread
{
    my $self   = shift;
    my $socket = $self->{_socket};
    my %unread;
    if ( !$self->{_loggedin} )
    {
        return 0;
    }
    my %forums = $self->forums("todo");
    foreach my $key ( sort keys %forums )
    {
        my $unread_count = $forums{$key}->{todo};
        $unread{$key} = {
            unread    => $unread_count,
            name      => $forums{$key}->{name},
            firstnote => $forums{$key}->{firstnote},
            lastnote  => $forums{$key}->{lastnote}
        };
    }

    return (%unread);
}

sub get_fi
{
    my $self   = shift;
    my $socket = $self->{_socket};
    print $socket "SHOW info\n";
    my $result = <$socket>;
    return 0 unless ( $result =~ /^3/ );
    chomp( my $fromline = <$socket> );
    my $author = $1 if ( $fromline =~ /From: (.*)/ );
    chomp( my $dateline = <$socket> );
    my $date      = $1 if ( $dateline =~ /Date: (.*)/ );
    my $blankline = <$socket>;

    my @lines;

    while ( chomp( my $line = <$socket> ) )
    {
        last if ( $line =~ /^\.$/ );
        push( @lines, $line );
    }
    my $body = join( "\n", @lines );
    my $fi = { fi_author => $author, last_updated => $date, body => $body };
    return $fi;
}

sub logout
{
    my $socket = $_[0]->{_socket};
    print $socket "QUIT\n";
    $socket->close() or return 0;
}

1;

__END__

=head1 NAME

Net::ISCABBS - Perl interface to the ISCABBS system

=head1 SYNOPSIS

  use Net::ISCABBS;

  # Create a new BBS object by logging in with your account
  # If you leave off the login and password, you'll log in with
  # unauthenticated rights, NOT as the user "Guest".
  my $bbs = new Net::ISCABBS(login=>"Bugcrusher", password=>"mypass");
 
  # Show the forums that you are a member of.  The hash key is the 
  # forum number.  Doesn't work for unauthenticated users.
  my %forums = $bbs->forums("joined");

  # Get the number for all joined forums with unread messages.
  my %unread = $bbs->forums_with_unread;
  
  foreach my $forum (sort keys %unread)
  {
    print "There are $unread{$forum}->{unread} unread messages in $unread{$forum}->{name}\n";
  }

  # Make the Unix forum your active one.  You can jump by number or by
  # name.
  my $forum = $bbs->jump("Unix") or die "Couldn't join forum!\n";
  print "Joined Forum $forum->{name}, adminned by $forum->{admin}\n";
  
  # Get the forum information for your active forum
  my $fi = $bbs->get_fi;
  print "Forum Info author is $fi->{fi_author}\n";
  print "\n$fi->{body}\n\n";

  # Read all new messages in the current forum
  while (my $message = $bbs->read)
  {
    print "\n\nNEW MESSAGE\n";
    print "From: $message->{author}\n";
    print "Date: $message->{date}\n";
    print "$message->{body}\n";
  }

  # Log out
  $bbs->logout;

=head1 DESCRIPTION

Established in 1989, ISCABBS has provided a virtual community for students of the University of Iowa and the Internet in general. Today ISCABBS is the world's largest free bulletin board system on the Internet, with over 5,000 active members. We have a validation structure to help prevent harassment while allowing for anonymity, a team of System Operators who help to maintain a near round the clock watch on activities, and nearly 200 discussion forums which cover a wide variety of topics, from the intensely technical to the sublimely silly.

The base code for ISCABBS is D.O.C. (Daves' Own Citadel), a telnet-based BBS code derived originally from Citadel. The D.O.C. code was written primarily by Dr. David Lacey, then a student at the University of Iowa. In 2001 the code for D.O.C. was released under the GNU General Public License. Several variants have already been developed from this base code.

ISCABBS offers Intra-BBS electronic mail and real-time instant messages between users and a variety of forums covering many areas of academic and social discussion,  as well as general discussion forums.

ISCABBS is owned and maintained by the Iowa Student Computer Association at the University of Iowa in Iowa City, Iowa. This student group meets monthly during the school year and supports several projects.

A developer's interface to ISCABBS was opened in September 2004.  This module allows Perl coders to access that interface.

=head1 METHODS

=over 4

=item $bbs = new Net::ISCABBS(host=>"bbs.isca.uiowa.edu", port=>"6145", login=>"Bugcrusher", password=>"mypass");

This creates a new BBS object with the supplied parameters.  All are optional - if you leave off the host and port, the defaults shown above will be used.  If you do not supply the username and the password, you will gain access as an unauthenticated user (NOT the ISCABBS "Guest" account).  That will disable a couple of methods involving joined forums, though, since you have to be authenticated to join some forums.

If there is a socket problem or the username and password you supply will not work, the function returns 0.

=item %forums = $bbs->forums(TYPE);

Returns a hash of information about forums, specified by TYPE.  If you omit the TYPE, you will get information about all forums that you can see.

The TYPE can be: all, private, public, todo, recent, joined.  "joined" will probably be the most useful of the bunch.  "todo" shows you forums with unread messages, but that is exposed via the $bbs->forums_with_unread method, so you'll probably want to use that instead of $bbs->forums("todo");

The hash returned is keyed by forum number, which itself is a hash reference containing the following information.

$forums{$i}->{name} - The ASCII forum name.

$forums{$i}->{lastnote} - The number of the last message posted in the forum.

$forums{$i}->{flags} - The permission flags for the forum.

=item my $forum = $bbs->jump("Late");

Switches your active forum to the one specified.  You can either jump based on forum number, or by the name of the forum (first match wins).  Only one forum can be active at a time per connection.

Returns a hash reference that contains some or all the following keys:

$forum->{topic} - The forum number

$forum->{name} - The ASCII name of the forum

$forum->{lastnote} - The numeric message ID of the newest message in the forum.

$forum->{firstnote} - The numeric message ID of the oldest message in the forum.

$forum->{admin} - The ISCA username of the forum moderator.

=item my %headers = $bbs->get_forum_headers;

Returns a hash, where the keys are the post numbers and the value is a hash reference containing the following information:

$headers{$postnum}->{author} - The ISCABBS username of the author

$headers{$postnum}->{date} - The posting date

$headers{$postnum}->{subject} - A simple subject for the post, taken from the first few words.

=item my %unread = $bbs->forums_with_unread;

Returns a hash, where the keys are the forum numbers and the value is a hash reference containing the following information:

$unread{$forum_number}->{name} - The ASCII name of the forum

$unread{$forum_number}->{unread} - The count of unread messages in that forum.

$unread{$forum_number}->{firstnote} - The numeric message ID of the oldest message in the forum.

$unread{$forum_number}->{lastnote} - The numeric message ID of the newest message in the forum.

This method does not work if you are unauthenticated.

=item my $fi = $bbs->get_fi;

Returns a hash reference of the forum information for the active forum.

$fi->{fi_author} - The author of the forum information for the active forum

$fi->{last_updated} - The date that the forum information was modified

$fi->{body} - The text of the forum information

=item $first = $bbs->get_first_unread;

Gets the numeric message ID of the first message in your currently active forum that you have not read.

=item my $message = $bbs->read($message_number);

Returns a hashref containing the message in your currently active forum at ID $message_number or, if you do not specify one, your first unread message.

The hashref contains the following fields:

$message->{author} - The author of the post.

$message->{date} - The date the post was made.

$message->{body} - The body of the post.

The $bbs->read method increments your "last read" counter, so that you can read all unread messages with the following loop:

while (my $message = $bbs->read)
{
  print "From: $message->{author}\n";
  print "Date: $message->{date}\n";
  print "$message->{body}\n";
}

=item $bbs->set_first_unread($messageid)

Sets the flag for your first unread message to the number specified in $messageid.  Returns failure if the specified number is outside of the bounds of the first and last messages currently in the forum, success otherwise.

=item $bbs->logout;

Sends a QUIT to the BBS and closes the TCP socket

=head1 BUGS

Currently the module works in read-only mode.  Posting and deleting are not yet working.

This is my first Perl module, so there are probably many things that could be done better.   Patches welcome!

=head1 SEE ALSO

ISCABBS Website: L<http://www.iscabbs.com/>

Telnet to bbs.isca.uiowa.edu to participate in ISCABBS.

For more information on the programmer's interface, post in the The Future Of ISCA BBS> forum on ISCA.

=head1 AUTHOR

H. Wade Minter, E<lt>minter@lunenburg.orgE<gt>
L<http://www.lunenburg.org/>

=head1 COPYRIGHT AND LICENSE

Copyright 2004 by H. Wade Minter

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself. 

=cut
