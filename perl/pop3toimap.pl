#!/usr/bin/perl

########################################################################
#                                                                      #
#   Program Name    pop3toimap.pl                                      #
#   Written by      Rick Sanders                                       #  
#   Date            28 April 2008                                      #
#                                                                      #
#   Description                                                        #
#                                                                      #
#   pop3toimap.pl is a tool for copying a user's messages from a POP3  #
#   server to an IMAP4 server.  pop3toimap.pl makes a POP3 connection  #
#   to the POP3 host and logs in with the user's name and password.    #
#   It makes an IMAP connection to the IMAP host and logs in with the  #
#   user's IMAP username and password.  pop3toimap.pl then fetches     #
#   each message from the user's POP3 account and copies it to the     #
#   user's IMAP account.                                               #
#                                                                      #
#   If you supply 993 for the IMAP port then the connection will be    #
#   made over SSL.  Similarily for POP if you specify port 995. Note   #
#   you must have the IO::Socket::SSL Perl module installed as well    #
#   as openSSL.                                                        #
#                                                                      #
#   The usernames and passwords are supplied via a text file specified #
#   by the -u argument.  The format of the file of users is:           #
#      <popUsername> <password> <imapUsername> <password>              #
########################################################################

use Getopt::Std;
use Socket;
use IO::Socket;

   init();

   if ( $usersFile ) {
      $imapHost = $opt_i;
      $popHost  = $opt_p;
      getUsersList( $usersFile, \@users );
   } else {
      #  Single user
      ($imapHost,$imapUser,$imapPwd) = split(/\//, $opt_i);
      ($popHost,$popUser,$popPwd)    = split(/\//, $opt_p);
      push( @users, "$popUser $popPwd $imapUser $imapPwd" );
   }
   ($imapHost,$imapPort) = split(/:/, $imapHost);
   ($popHost,$popPort)  = split(/:/, $popHost);
   $imapPort = 143 unless $imapPort;
   $popPort  = 110 unless $popPort;

   foreach $line ( @users ) {
      $line =~ s/\s+/ /g;
      ($popUser,$popPwd,$imapUser,$imapPwd) = split(/ /, $line);

      #  Connect to the POP server and login
      connectToHost($popHost, $popPort, \$p_conn);
      next unless loginPOP( $popUser, $popPwd, $p_conn );

      #  Connect to the IMAP server and login
      connectToHost($imapHost, $imapPort, \$i_conn);
      next unless loginIMAP( $imapUser, $imapPwd, $i_conn );

      migrate( $p_conn, $i_conn );
      logoutPOP( $p_conn );
      logoutIMAP( $i_conn );
   }

   summary();
   exit;


#
#  migrate
#
#  Get a list of messages in the POP user's account, retrieve each one from
#  the POP server, and insert each one into the IMAP user's account.  Delete
#  the message from the POP server if the "delete" flag is set.
#
sub migrate {

my $p_conn = shift;
my $i_conn = shift;
my $copied;

   if ( $range ) {
      ($lower,$upper) = split(/-/, $range);
      print STDOUT "Migrating POP messages between $lower and $upper\n";
      Log("Migrating POP message numbers between $lower and $upper");
   }

   @popMsgList = getPOPMsgList( $p_conn );

   if ( $debug ) {
      Log("List the POP msgs by message number");
      foreach $msg ( @popMsgList ) {
         Log("$msg");
      }
   }

   $count = $#popMsgList + 1;
   Log("Migrating $popUser on $popHost to $imapUser on $imapHost ($count messages)");

   foreach $msgnum ( @popMsgList ) {
      if ( $range ) {
         Log("msgnum $msgnum") if $debug;
         next if $msgnum < $lower;
         next if $msgnum > $upper;
      }
      Log("Fetching POP message $msgnum") if $debug;
      $msg = getPOPMsg( $msgnum, $p_conn );

      getFlag( \$msg, \$flag );
      getDate( \$msg, \$date );

      next if $msg eq '';

      if ( insertMsg(*msg, "INBOX", $date, $flag, $i_conn ) ) {
         $copied++;
         $grandTotal++;
         Log("$copied messages migrated") if $copied/100 == int($copied/100);

	 #  Delete the message from the POP server if the delete flag is set
	 deletePOPMsg( $msgnum, $p_conn ) if $delete;

      }
   }

   $usersMigrated++;
}


sub init {

   $version = "1.3";

   getopts( "Ip:L:i:u:n:drhR:S" );

   $usersFile = $opt_u;
   $logFile   = $opt_L;
   $notify    = $opt_n;
   $range     = $opt_R;
   $delete    = 1 if $opt_r;
   $debug     = 1 if $opt_d;
   $showIMAP  = 1 if $opt_I;

   usage() if $opt_h;

   #  Determine whether we have SSL support via openSSL and IO::Socket::SSL
   $ssl_installed = 1;
   eval 'use IO::Socket::SSL';
   if ( $@ ) {
      $ssl_installed = 0;
   }

   $logFile = "pop3toimap.log" unless $logFile;
   if (!open(LOG, ">> $logFile")) {
        print STDERR "Can't open logfile $logFile\n";
	exit;
   }
   select(LOG); $| = 1;
   Log("pop3toimap $version starting");

   $timeout = 45;

}

sub getUsersList {

my $usersFile = shift;
my $users = shift;

   #  Get the list of users to be migrated
   #
   unless ( -e $usersFile ) {
      print STDERR "$usersFile does not exist\n";
      exit;
   }

   if ( !open(USERS, "<$usersFile")) {
        print STDERR "pop3toimap, Can't open $usersFile for input\n";
        Log("Can't open $usersFile for input");
        exit 0;
   }
   while (<USERS>) {
         chop;
	 next if /^\#/;
         push (@$users, $_) if $_;
   }
   close USERS;
   $totalUsers = $#users + 1;
   Log("There are $totalUsers users to be migrated");
}

sub procArgs {



}

#  Make a connection to a host

sub connectToHost {

my $host = shift;
my $port = shift;
my $conn = shift;

   Log("Connecting to $host") if $debug;
   
   # We know whether to use SSL for the well-known ports (143,993,110,995) but
   #  for any others we'll have to figure it out.
   $mode = sslmode( $host, $port );

   if ( $mode eq 'SSL' ) {
      unless( $ssl_installed == 1 ) {
         warn("You must have openSSL and IO::Socket::SSL installed to use an SSL connection");
         Log("You must have openSSL and IO::Socket::SSL installed to use an SSL connection");
         exit;
      }
      Log("Attempting an SSL connection") if $debug;
      $$conn = IO::Socket::SSL->new(
         Proto           => "tcp",
         SSL_verify_mode => 0x00,
         PeerAddr        => $host,
         PeerPort        => $port,
      );

      unless ( $$conn ) {
        $error = IO::Socket::SSL::errstr();
        Log("Error connecting to $host: $error");
        warn("Error connecting to $host: $error");
        exit;
      }
   } else {
      #  Non-SSL connection
      Log("Attempting a non-SSL connection") if $debug;
      $$conn = IO::Socket::INET->new(
         Proto           => "tcp",
         PeerAddr        => $host,
         PeerPort        => $port,
      );

      unless ( $$conn ) {
        Log("Error connecting to $host:$port: $@");
        warn "Error connecting to $host:$port: $@";
        exit;
      }
   } 
   Log("Connected to $host on port $port");

}

sub sslmode {

my $host = shift;
my $port = shift;
my $mode;

   #  Determine whether to make an SSL connection
   #  to the host.  Return 'SSL' if so.

   if ( $port == 143 or $port == 110 ) {
      #  Standard non-SSL ports
      return '';
   } elsif ( $port == 993 or $port == 995 ) {
      #  Standard SSL ports
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

#  loginPOP
#
#  login in at the POP host with the user's name and password
#
sub loginPOP {

my $user = shift;
my $pwd  = shift;
my $conn = shift;
my $rc;

   Log("Authenticating to POP server as $user, password $pwd") if $debug;

   sendCommand ($conn, "USER $user" );
   while ( 1 ) {
        readResponse ($conn);
	if ( $response =~ /^-ERR/i ) {
	   Log("Error logging into the POP server as $popUser: $response");
	   $rc = 0;
	   last;
	}
        # last if $response =~ /^(.+)OK /i;
        last if $response =~ /^(.+)OK Pass required/i;
   }

   Log("Send the password") if $debug;
   sendCommand ($conn, "PASS $pwd" );
   while ( 1 ) {
        readResponse ($conn);
	if ( $response =~ /^-ERR/i ) {
	   Log("Error logging into the POP server as $popUser: $response");
	   $rc = 0;
	   last;
	}
        if ( $response =~ /^\+OK/i ) {
	   $rc = 1;
	   Log("Logged in as $popUser") if $debug;
           last;
	}
   }

   return $rc;

}

#  loginIMAP
#
#  login in to the IMAP server
#
sub loginIMAP {

my $user = shift;
my $pwd  = shift;
my $conn = shift;

   $rsn = 1;
   sendCommand ($conn, "$rsn LOGIN $user $pwd");
   while (1) {
	readResponse ($conn);
	if ($response =~ /^$rsn OK/i) {
		last;
	}
	elsif ($response !~ /^\*/) {
		Log ("Error logging into the IMAP server as $user: $response");
		return 0;
	}
   }
   Log("Logged in at $imapHost as $user") if $debug;

   return 1;
}

#
#  getPOPMsgList
#
#  Get a list of the messages in the POP user's account.
#
sub getPOPMsgList {

my $conn = shift;
my @msgList;

   sendCommand ($conn, "LIST" );
   while ( 1 ) {
	readResponse ($conn);

	next if $response =~ /^\+OK/i;
	if ( $response =~ /^\-ERR/i ) {
	   Log("Error getting list of POP messages: $response");
	}
        elsif ( $response eq '.' ) {
	   last;
	}
	else {
	   ($msgnum, $uid) = split(/ /, $response);
	   push(@msgList, $msgnum);
	}
   }

   return @msgList;
}


#
#  getPOPMsg
#
#  Fetch a message from the user's account on the POP server

sub getPOPMsg { 

my $msgnum = shift;
my $conn   = shift;
my $msg;

   sendCommand ($conn, "RETR $msgnum" );
   while ( 1 ) {
        readResponse ($conn);
        # Log("$response");

        next if $response =~ /^\+OK/i;

        if ( $response =~ /^\-ERR/i ) {
           Log("Error getting POP message $msg: $response");
	   $msg = '';
	   last;
        }
        elsif ( $response eq '.' ) {
           last;
        }
	else {
	   $msg .= "$response\r\n";
 	}
   }

   return $msg;

}


#
#  deletePOPMsg
#
#  Delete a message from the POP server

sub deletePOPMsg { 

my $msgnum = shift;
my $conn   = shift;
my $msg;

   sendCommand ($conn, "DELE $msgnum" );
   while ( 1 ) {
        readResponse ($conn);
        Log("$response") if $debug;

        last if $response =~ /^\+OK/i;

        if ( $response =~ /^\-ERR/i ) {
           Log("Error marking POP message $msg for delete: $response");
	   last;
        }
   }
   return;

}


#  readResponse
#
#  Read the response from the server on the designated socket.
#
sub readResponse {

my $fd = shift;

    @response = ();
    alarmSet ($timeout);
    $response = <$fd>;
    alarmSet (0);
    chop $response;
    $response =~ s/\r//g;
    push (@response,$response);
    Log ("<< $response") if $showIMAP;

    return $response;
}

#
#  alarmHandler
#
#  This subroutine catches response timeouts and attempts to reconnect
#  to the host so that processing can continue
#

sub alarmHandler {
    Log ("Timeout - no response from server after $timeout seconds");
    Log("Reconnect to server and continue");
	
    connectToPOP( $popHost );
    loginPOP( $popUser, $popPwd, $p_conn );

    connectToIMAP( $imapHost, $i_conn );
    loginIMAP( $imapUser, $imapPwd, $i_conn );

    return;
}


#  insertMsg
#
#  This routine inserts a messages into a user's IMAP INBOX
#
sub insertMsg {

local (*message, $mbx, $date, $flag, $conn) = @_;
local ($rsn,$lenx);

   $lenx = length($message);
   $totalBytes = $totalBytes + $lenx;
   $totalMsgs++;

   ++$rsn;

   if ( $date ) {
      ($date,$time,$offset) = split(/\s+/, $date);
      ($hr,$min,$sec) = split(/:/, $time);
      $hr = '0' . $hr if length($hr) == 1;
      $date = "$date $hr:$min:$sec $offset";
      $cmd = "$rsn APPEND \"$mbx\" $flag \"$date\" \{$lenx\}";
   } else {
      $cmd = "$rsn APPEND \"$mbx\" $flag \{$lenx\}";
   }
   $cmd =~ s/\s+/ /g;
   sendCommand ($conn, "$cmd");
   readResponse ($conn);
   if ( $response !~ /^\+/ ) {
       Log ("unexpected APPEND response: $response");
       push(@errors,"Error appending message to $mbx for $user");
       return 0;
   }

   print $conn "$message\r\n";

   undef @response;
   while ( 1 ) {
       readResponse ($conn);
       if ( $response =~ /^$rsn OK/i ) {
	   last;
       }
       elsif ( $response !~ /^\*/ ) {
	   Log ("unexpected APPEND response: $response");
	   # next;
	   return 0;
       }
   }

   return 1;
}

#  alarmSet
#
#  This subroutine sets an alarm
#

sub alarmSet {
    local ($timeout) = @_;

    if ( $nt ) {
        alarm $timeout;
    }
}

#  Log
#
#  This subroutine formats and writes a log message to STDOUT and to the
#  logfile.
#
sub Log {

my $str = shift;
my $line;

    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
    if ($year < 99) { $yr = 2000; }
    else { $yr = 1900; }
    $line = sprintf ("%.2d-%.2d-%d.%.2d:%.2d:%.2d %s %s\n",
		     $mon + 1, $mday, $year + $yr, $hour, $min, $sec,$$,$str);

    print LOG "$line";
    print STDOUT "$str\n";
    
   if ( !$start ) {
         $start = sprintf ("%.2d-%.2d-%d %.2d:%.2d",
		     $mon + 1, $mday, $year + $yr, $hour, $min);
   }
}

#  sendCommand
#
#  This subroutine formats and sends a command  on the designated
#  socket
#
sub sendCommand {

my $fd = shift;
my $cmd = shift;

   print $fd "$cmd\r\n";
   Log (">> $cmd") if $debug;
}

#  logoutIMAP
#
#  log out from the IMAP host
#
sub logoutIMAP {

my $conn = shift;

   ++$rsn;
   sendCommand ($conn, "$rsn LOGOUT");
   while ( 1 ) {
	readResponse ($conn);
	if ( $response =~ /^$rsn OK/i ) {
		last;
	}
	elsif ( $response !~ /^\*/ ) {
		Log ("unexpected LOGOUT response: $response");
		last;
	}
   }
   close $conn;

   return;

}

#  logoutPOP
#
#  log out from the POP host
#
sub logoutPOP {

my $conn = shift;

   sendCommand ($conn, "QUIT");
   while ( 1 ) {
	readResponse ($conn);
	if ( $response =~ /^\+OK/i ) {
	   last;
	}
	else  {
	   Log ("unexpected POP QUIT response: $response");
	   last;
	}
   }
   close $conn;

}

sub summary {

   $line = "\n       Summary of POP3 -> IMAP migration\n\n";
   $line .= "Users migrated  $usersMigrated\n";
   $line .= "Total messages  $totalMsgs\n";
   $line .= "Total bytes     $totalBytes\n";

   Log($line);
   notify($notify,$line) if $notify;
}

sub usage {

   print "\n";
   print "pop3toimap.pl usage:\n";
   print "   -p <POP3 host/user/password>\n";
   print "   -i <IMAP host/user/password>\n";
   print "   -u <input file>\n";
   print "   -d debug mode\n";
   print "   -n <notify e-mail address>\n";
   print "   -r delete POP3 message after migrating to IMAP\n";
   print "   -L <logfile>\n";
   print "   -I show IMAP protocol exchanges\n";
   print "   -h print this message\n\n";
   print "\nYou can migrate a single user with -p POPhost/user/pwd -i IMAPhost/user/pwd\n";
   print "or a list of users with -i POPhost -i IMAPhost -u <list of users>.\n";
   print "The format of the input file is:\n\n";
   print "<POP3 username> <POP3 user password> <IMAP username> <IMAP user password>\n\n"; 

   exit;
}

#
#  Send an e-mail with the results of the migration
#
sub notify {

my $to = shift;
my $text = shift;

   Log("Notifying $to") if $debug;

   $end = sprintf ("%.2d-%.2d-%d %.2d:%.2d\n",
                     $mon + 1, $mday, $year + $yr, $hour, $min);

   $msgFn = "/tmp/msg.tmp.$$";
   open (MSG, ">$msgFn");
   print MSG "To: $to\n";
   print MSG "From: pop3toimap.migration\n";
   print MSG "Subject: pop3toimap migration has completed $end\n";
   print MSG "\n";
   print MSG "$line\n\n";
   print MSG "Start $start\n";
   print MSG "End   $end\n";
   close MSG;

   $status = system("/usr/lib/sendmail -t < $msgFn")/256;
   if ($status != 0) {
      print "Error sending report to $notify: $status\n";
   }
   unlink $msgFn;

}

sub getFlag {

my $msg  = shift;
my $flag = shift;

   #  The POP3 protocol does not indicate whether a message is SEEN or
   #  UNSEEN so we will look in the message itself for a Status: line.
   $$flag = '';
   foreach $_ ( split(/\n/, $$msg) ) {
      chomp;
      last unless $_;
      if ( /Status/i ) {
         $$flag = '(\\SEEN)' if /^Status:\s*R/i;
         last;
      }
   }

}

sub getDate {

my $msg  = shift;
my $Date = shift;
my $letter;
my $newdate;

   $$Date = '';
   foreach $line ( split(/\n/, $$msg) ) {
      next unless $line =~ /^Date: (.+)/i;
      chomp( $date = $1 );
      $date =~ s/\n|\r//g;
      ($day,$date) = split(/,\s*/, $date);

      my $changed;
      for $i ( 0 .. length($date) ) {
         $letter = substr($date, $i, 1);
         if ( substr($date, $i, 1) eq ' ') {
            $letter = "-" unless $changed > 1;
            $changed++;
         } 
         $newdate .= $letter;
      }
   }
   $newdate =~ s/EDT|EST|CDT|CST|PDT|PST|\(|\)/+0000/g;
   $newdate =~ s/\s+$//;
   unless ( $newdate =~ /\-(.+)\s*$/ ) {
       $newdate .= " -0000";
   }

   $newdate = '' if $newdate eq " -0000";

   $$Date = $newdate;

}
