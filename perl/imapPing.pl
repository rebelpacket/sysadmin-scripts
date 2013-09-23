#!/usr/bin/perl

#######################################################################
#   Program   imapPing.pl                                             #
#   Date      20 January 2008                                         #
#                                                                     #
#   Description                                                       #
#      This script performs some basic IMAP operations on a user's    #
#      account and displays the time as each one is executed.  The    #
#      operations are:                                                #
#           1.  Connect to the IMAP server                            #
#           2.  Log in with the user's name and password              #
#           3.  Get a list of mailboxes in the user's account         #
#           4.  Select the INBOX                                      #
#           5.  Get a list of messages in the INBOX                   #
#           6.  Log off the server                                    #
#                                                                     #
#   Usage: imapPing.pl -h <host> -u <user> -p <password>              #
#                                                                     #
#######################################################################

use Getopt::Std;
use Socket;
use FileHandle;
use Fcntl;

   init();
   ($host,$user,$pwd) = getArgs(); 

   print STDOUT pack( "A35 A10", "Connecting to $host", getTime() );
   connectToHost( $host, \$conn );

   print STDOUT pack( "A35 A10","Logging in as $user", getTime() );
   login( $user,$pwd, $conn );

   print STDOUT pack( "A35 A10","Get list of mailboxes", getTime() );
   getMailboxList( $conn );

   print STDOUT pack( "A35 A10","Selecting the INBOX", getTime() );
   selectMbx( 'INBOX', $conn ) if $rc;

   print STDOUT pack( "A35 A10","Get list of msgs in INBOX", getTime() );
   getMsgList( 'INBOX', $conn );

   print STDOUT pack( "A35 A10","Logging out", getTime() );
   logout( $conn );

   print STDOUT pack( "A35 A10","Done", getTime() );
   
   exit;
   
   exit 1;


sub init {

   #  Determine whether we have SSL support via openSSL and IO::Socket::SSL
   $ssl_installed = 1;
   eval 'use IO::Socket::SSL';
   if ( $@ ) {
      $ssl_installed = 0;
   }

   getTime();
   $debug = 1;
}

sub getTime {

   ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
   if ($year < 99) { $yr = 2000; }
   else { $yr = 1900; }
   $date = sprintf ("%.2d-%.2d-%d.%.2d:%.2d:%.2d \n",
		$mon+1,$mday,$year+$yr,$hour,$min,$sec);
   $time = sprintf ("%.2d:%.2d:%.2d \n",$hour,$min,$sec);

   return $time;
}

sub getArgs { 

   getopts( "h:u:p:" );
   $host = $opt_h;
   $user = $opt_u;
   $pwd  = $opt_p;
   $showIMAP = 1 if $opt_I;

   if ( $opt_H ) {
	usage();
   }

   unless ( $host and $user and $pwd ) {
	usage();
        exit;
   }


   return ($host,$user,$pwd);   

}

#  sendCommand
#
#  This subroutine formats and sends an IMAP protocol command to an
#  IMAP server on a specified connection.
#

sub sendCommand
{
    local($fd) = shift @_;
    local($cmd) = shift @_;

    print $fd "$cmd\r\n";
    print STDOUT ">> $cmd\n" if $showIMAP;
}

#
#  readResponse
#
#  This subroutine reads and formats an IMAP protocol response from an
#  IMAP server on a specified connection.
#

sub readResponse
{
    local($fd) = shift @_;

    $response = <$fd>;
    chop $response;
    $response =~ s/\r//g;
    push (@response,$response);
    print STDOUT "<< $response\n" if $showIMAP;
}

#  Make a connection to an IMAP host

sub connectToHost {

my $host = shift;
my $conn = shift;

   ($host,$port) = split(/:/, $host);
   $port = 143 unless $port;

   # We know whether to use SSL for ports 143 and 993.  For any
   # other ones we'll have to figure it out.
   $mode = sslmode( $host, $port );

   if ( $mode eq 'SSL' ) {
      unless( $ssl_installed == 1 ) {
         warn("You must have openSSL and IO::Socket::SSL installed to use an SSL connection");
         exit;
      }
      $$conn = IO::Socket::SSL->new(
         Proto           => "tcp",
         SSL_verify_mode => 0x00,
         PeerAddr        => $host,
         PeerPort        => $port,
      );

      unless ( $$conn ) {
        $error = IO::Socket::SSL::errstr();
        warn("Error connecting to $host: $error");
        exit;
      }
   } else {
      #  Non-SSL connection
      $$conn = IO::Socket::INET->new(
         Proto           => "tcp",
         PeerAddr        => $host,
         PeerPort        => $port,
      );

      unless ( $$conn ) {
        warn "Error connecting to $host:$port: $@";
        exit;
      }
   } 

}

sub sslmode {

my $host = shift;
my $port = shift;
my $mode;

   #  Determine whether to make an SSL connection
   #  to the host.  Return 'SSL' if so.

   if ( $port == 143 ) {
      #  Standard non-SSL port
      return '';
   } elsif ( $port == 993 ) {
      #  Standard SSL port
      return 'SSL';
   }
      
   unless ( $ssl_installed ) {
      #  We don't have SSL installed on this machine
      return '';
   }

   #  For any other port we need to determine whether it supports SSL

   my $conn = IO::Socket::SSL->new(
         Proto           => "tcp",
         SSL_verify_mode => 0x00,
         PeerAddr        => $host,
         PeerPort        => $port,
    );

    if ( $conn ) {
       close( $conn );
       $mode = 'SSL';
    } else {
       $mode = '';
    }

   return $mode;
}


#  login
#
#  login in at the source host with the user's name and password
#
sub login {

my $user = shift;
my $pwd  = shift;
my $conn = shift;

   sendCommand ($conn, "1 LOGIN $user $pwd");
   while (1) {
	readResponse ($conn);
	if ($response =~ /^1 OK/i) {
	   last;
	}
	elsif ($response !~ /^\*/) {
	   print STDOUT "Unexpected login response $response\n";
	   return 0;
	}
   }

   return 1;
}


#  logout
#
#  log out from the source host
#
sub logout {

my $conn = shift;

   # print STDOUT "Logging out\n" if $debug;
   sendCommand ($conn, "1 LOGOUT");
   while ( 1 ) {
	readResponse ($conn);
	if ( $response =~ /^1 OK/i ) {
	   last;
	}
	elsif ( $response !~ /^\*/ ) {
	   print STDOUT "unexpected LOGOUT response: $response\n";
	   last;
	}
   }
   close $conn;

   return;

}

  
sub usage {

   print STDOUT "\nUsage: imapPing.pl <args> \n\n";
   print STDOUT "   -h   <hostname>\n";
   print STDOUT "   -u   <user>\n"; 
   print STDOUT "   -p   <password>\n";

   exit;

}


sub selectInbox {

my $mbx  = shift;
my $conn = shift;

   #  Select a mailbox

   sendCommand ($conn, "1 SELECT $mbx");
   while (1) {
	readResponse ($conn);
	if ($response =~ /^1 OK/i) {
	   last;
	}
	elsif ($response !~ /^\*/) {
	   print STDOUT "Unexpected SELECT INBOX response: $response\n";
	   return 0;
	}
   }

}

sub getMailboxList {

my $conn = shift;

   #  Get a list of the user's mailboxes
   
   sendCommand ($conn, "1 LIST \"\" *");
   @response = ();
   while ( 1 ) {
      readResponse ($conn);
      last if $response =~ /^1 OK/i;
	
      if ( $response !~ /^\*/ ) {
	 print STDOUT "unexpected response: $response\n";
         return 0;
      }
   }

   @mbxs = ();
   for $i (0 .. $#response) {
	# print STDERR "$response[$i]\n";
	$response[$i] =~ s/\s+/ /;
	($dmy,$mbx) = split(/"\/"/,$response[$i]);
	$mbx =~ s/^\s+//;  $mbx =~ s/\s+$//;
	$mbx =~ s/"//g;

	if ($mbx =~ /^\#/) {
	   #  Skip public mbxs
	   next;
	}

	if ($mbx ne '') {
	   push(@mbxs,$mbx);
	}
   }

   return 1;
}

sub getMsgList {

my $mailbox = shift;
my $conn    = shift;

   #  Select the mailbox in read-only mode

   sendCommand ($conn, "1 EXAMINE \"$mailbox\"");
   undef @response;
   $empty=0;
   while ( 1 ) {
    	readResponse ($conn);

        last if $response =~ /^1 OK/i;
    	
    	if ( $response !~ /^\*/ ) {
	   print STDOUT "Error: $response\n";
	   return 0;
    	}
   }

   sendCommand ($conn, "1 FETCH 1:* (UID FLAGS)");
   undef @response;
   while ( 1 ) {
	readResponse ($conn);
    	last if $response =~ /^1 OK/i;
        if ( $response !~ /^\*/ ) {
           print STDOUT "Unexpected response: $response\n";
	   return 0;
    	}
   }

   #  Get a list of the msgs in the mailbox
   #
   undef @msgs;
   for $i (0 .. $#response) {
	$_ = $response[$i];
        $_ =~ /\* ([^FETCH]*)/;
	$uid = $1;
	$uid =~ s/\s+$//;
   	if ($response[$i] =~ /\\Seen/) { $seen = 1; }
	if (($uid ne 'OK') && ($uid ne '')) {
		push (@msgs,"$uid $seen");
	}
   }
   return 1;
}
