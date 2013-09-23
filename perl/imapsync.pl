#!/usr/bin/perl

#######################################################################
#   Program name    imapsync.pl                                       #
#   Written by      Rick Sanders                                      #
#   Date            4/17/2003                                         #
#                                                                     #
#   Description                                                       #
#                                                                     #
#   imapsync is a utility for synchronizing a user's account on two   #
#   IMAP servers.  When supplied with host/user/password information  #
#   for two IMAP hosts imapsync does the following:                   #
#	1.  Adds any messages on the 1st host which aren't on the 2nd #
#       2.  Deletes any messages from the 2nd which aren't on the 1st #
#       3.  Sets the message flags on the 2nd to match the 1st's flags#  
#                                                                     #
#   imapsync is called like this:                                     #
#      ./imapsync -S host1/user1/password1 -D host2/user2/password2   # 
#                                                                     #
#   Optional arguments:                                               #
#	-d debug                                                      #
#       -L logfile                                                    #
#       -m mailbox list (sync only certain mailboxes,see usage notes) #
#######################################################################

use Socket;
use FileHandle;
use Fcntl;
use Getopt::Std;


#################################################################
#            Main program.                                      #
#################################################################

   &init();

   #  Get list of all messages on the source host by Message-Id
   #
   &connectToHost($sourceHost, 'SRC');
   &login($sourceUser,$sourcePwd, 'SRC');
   @mbxs = &getMailboxList($sourceUser, 'SRC');
   foreach $mbx ( @mbxs ) {
	&getMsgList( $mbx, \@sourceMsgs, 'SRC' ); 
   }

   #  Get list of all messages on the destination host by Message-Id
   
   &connectToHost( $destHost, 'DST' );
   &login( $destUser,$destPwd, 'DST' );
   undef @mbxs;
   @mbxs = &getMailboxList($destUser, 'DST' );
   foreach $mbx ( @mbxs ) {
        &getMsgList( $mbx, \@destMsgs, 'DST' );
   }

   #  Build two arrays of messages, one for the source and one for the dest

   foreach $entry ( @sourceMsgs ) {
	($msgid,$mbx,$rest) = split(/\|\|\|\|\|\|/, $entry,3);
        print STDOUT "   SRC  $mbx  $msgid\n" if $debug;
	$sourceList{"$msgid\|\|\|\|\|\|$mbx"} = $rest;
   }
   foreach $entry ( @destMsgs ) {
	($msgid,$mbx,$rest) = split(/\|\|\|\|\|\|/, $entry,3);
        print STDOUT "   DEST $mbx  $msgid\n" if $debug;
	$destList{"$msgid\|\|\|\|\|\|$mbx"} = $rest;
   }

   @destkeys   = keys( %destList );
   @sourcekeys = keys( %sourceList );
   #  Add any messages in the source which are not in the dest
   $added = &checkForAdds();

   #  Update the message flags if they have changed on the source
   $updated = &checkForUpdates();

   #  Delete any messages in the dest which are not in the source
   $deleted = &checkForDeletes();

   &logout( 'SRC' );
   &logout( 'DST' );

   &Log("\nSummary of results");
   &Log("   Added   $added");
   &Log("   Updated $updated");
   &Log("   Deleted $deleted");

   exit;


sub init {

   $version = 'V1.0';
   $os = $ENV{'OS'};

   &processArgs;

   if ($timeout eq '') { $timeout = 60; }

   #  Open the logFile
   #
   if ( $logfile ) {
      if ( !open(LOG, ">> $logfile")) {
         print STDOUT "Can't open $logfile: $!\n";
      } 
      select(LOG); $| = 1;
   }
   &Log("\n$0 starting\n");

}

#
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

    if ($showIMAP) { &Log (">> $cmd",2); }
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
    if ($showIMAP) { &Log ("<< $response",2); }
}

#
#  Log
#
#  This subroutine formats and writes a log message to STDERR.
#

sub Log {
 
my $str = shift;

   #  If a logile has been specified then write the output to it
   #  Otherwise write it to STDOUT

   if ( $logfile ) {
      ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
      if ($year < 99) { $yr = 2000; }
      else { $yr = 1900; }
      $line = sprintf ("%.2d-%.2d-%d.%.2d:%.2d:%.2d %s %s\n",
		     $mon + 1, $mday, $year + $yr, $hour, $min, $sec,$$,$str);
      print LOG "$line";
   } else {
      print STDOUT "$str\n";
   }

}

#  insertMsg
#
#  This routine inserts an RFC822 messages into a user's folder
#
sub insertMsg {

local ($conn, $mbx, *message, $flags, $date) = @_;
local ($lsn,$lenx);

   &Log("   Inserting message") if $debug;
   $lenx = length($message);
   $totalBytes = $totalBytes + $lenx;
   $totalMsgs++;

   #  Create the mailbox unless we have already done so
   ++$lsn;
   if ($destMbxs{"$mbx"} eq '') {
	&sendCommand (DST, "$lsn CREATE \"$mbx\"");
	while ( 1 ) {
	   &readResponse (DST);
	   if ( $response =~ /^$rsn OK/i ) {
		last;
	   }
	   elsif ( $response !~ /^\*/ ) {
		if (!($response =~ /already exists|reserved mailbox name/i)) {
			&Log ("WARNING: $response");
		}
		last;
	   }
       }
   } 
   $destMbxs{"$mbx"} = '1';

   ++$lsn;
   $flags =~ s/\\Recent//i;

   &sendCommand (DST, "$lsn APPEND \"$mbx\" ($flags) \"$date\" \{$lenx\}");
   # &sendCommand (DST, "$lsn APPEND \"$mbx\" \{$lenx\}");
   &readResponse (DST);
   if ( $response !~ /^\+/ ) {
       &Log ("unexpected APPEND response: $response");
       # next;
       push(@errors,"Error appending message to $mbx for $user");
       return 0;
   }

   print DST "$message\r\n";

   undef @response;
   while ( 1 ) {
       &readResponse (DST);
       if ( $response =~ /^$lsn OK/i ) {
	   last;
       }
       elsif ( $response !~ /^\*/ ) {
	   &Log ("unexpected APPEND response: $response");
	   # next;
	   return 0;
       }
   }

   return;
}



#  connectToHost
#
#  Make an IMAP4 connection to a host
# 
sub connectToHost {

my $host = shift;
my $conn = shift;

   &Log("Connecting to $host") if $debug;

   $sockaddr = 'S n a4 x8';
   ($name, $aliases, $proto) = getprotobyname('tcp');
   $port = 143;

   if ($host eq "") {
	&Log ("no remote host defined");
	close LOG; 
	exit (1);
   }

   ($name, $aliases, $type, $len, $serverAddr) = gethostbyname ($host);
   if (!$serverAddr) {
	&Log ("$host: unknown host");
	close LOG; 
	exit (1);
   }

   #  Connect to the IMAP4 server
   #

   $server = pack ($sockaddr, &AF_INET, $port, $serverAddr);
   if (! socket($conn, &PF_INET, &SOCK_STREAM, $proto) ) {
	&Log ("socket: $!");    
	close LOG;
	exit (1);
   }
   if ( ! connect( $conn, $server ) ) {
	&Log ("connect: $!");
	return 0;
   }

   select( $conn ); $| = 1;
   while (1) {
	&readResponse ( $conn );
	if ( $response =~ /^\* OK/i ) {
	   last;
	}
	else {
 	   &Log ("Can't connect to host on port $port: $response");
	   return 0;
	}
   }
   &Log ("connected to $host") if $debug;

   select( $conn ); $| = 1;
   return 1;
}

#  trim
#
#  remove leading and trailing spaces from a string
sub trim {
 
local (*string) = @_;

   $string =~ s/^\s+//;
   $string =~ s/\s+$//;

   return;
}


#  login
#
#  login in at the source host with the user's name and password
#
sub login {

my $user = shift;
my $pwd  = shift;
my $conn = shift;

   $rsn = 1;
   &sendCommand ($conn, "$rsn LOGIN $user $pwd");
   while (1) {
	&readResponse ( $conn );
	if ($response =~ /^$rsn OK/i) {
		last;
	}
	elsif ($response =~ /NO/) {
		&Log ("unexpected LOGIN response: $response");
		return 0;
	}
   }
   &Log("Logged in as $user") if $debug;

   return 1;
}


#  logout
#
#  log out from the host
#
sub logout {

my $conn = shift;

   ++$lsn;
   undef @response;
   &sendCommand ($conn, "$lsn LOGOUT");
   while ( 1 ) {
	&readResponse ($conn);
	if ( $response =~ /^$lsn OK/i ) {
		last;
	}
	elsif ( $response !~ /^\*/ ) {
		&Log ("unexpected LOGOUT response: $response");
		last;
	}
   }
   close $conn;
   return;
}


#  getMailboxList
#
#  get a list of the user's mailboxes from the source host
#
sub getMailboxList {

my $user = shift;
my $conn = shift;
my @mbxs;
my @mailboxes;

   #  Get a list of the user's mailboxes
   #
  if ( $mbxList ) {
      #  The user has supplied a list of mailboxes so only processes
      #  the ones in that list
      @mbxs = split(/,/, $mbxList);
      foreach $mbx ( @mbxs ) {
         &trim( *mbx );
         push( @mailboxes, $mbx );
      }
      return @mailboxes;
   }

   if ($debugMode) { &Log("Get list of user's mailboxes",2); }

   &sendCommand ($conn, "$rsn LIST \"\" *");
   undef @response;
   while ( 1 ) {
	&readResponse ($conn);
	if ( $response =~ /^$rsn OK/i ) {
		last;
	}
	elsif ( $response !~ /^\*/ ) {
		&Log ("unexpected response: $response");
		return 0;
	}
   }

   undef @mbxs;
   for $i (0 .. $#response) {
	# print STDERR "$response[$i]\n";
	$response[$i] =~ s/\s+/ /;
	($dmy,$mbx) = split(/"\/"/,$response[$i]);
	$mbx =~ s/^\s+//;  $mbx =~ s/\s+$//;
	$mbx =~ s/"//g;

	if ($response[$i] =~ /NOSELECT/i) {
		if ($debugMode) { &Log("$mbx is set NOSELECT,skip it",2); }
		next;
	}
	if (($mbx =~ /^\#/) && ($user ne 'anonymous')) {
		#  Skip public mbxs unless we are migrating them
		next;
	}
	if ($mbx =~ /^\./) {
		# Skip mailboxes starting with a dot
		next;
	}
	push ( @mbxs, $mbx ) if $mbx ne '';
   }

   if ( $mbxList ) {
      #  The user has supplied a list of mailboxes so only processes
      #  those
      @mbxs = split(/,/, $mbxList);
   }

   return @mbxs;
}


#  getMsgList
#
#  Get a list of the user's messages in the indicated mailbox on
#  the source host
#
sub getMsgList {

my $mailbox = shift;
my $msgs    = shift;
my $conn    = shift;
my $seen;
my $empty;
my $msgnum;

   &trim( *mailbox );
   &sendCommand ($conn, "$rsn EXAMINE \"$mailbox\"");
   undef @response;
   $empty=0;
   while ( 1 ) {
	&readResponse ( $conn );
	if ( $response =~ / 0 EXISTS/i ) { $empty=1; }
	if ( $response =~ /^$rsn OK/i ) {
		# print STDERR "response $response\n";
		last;
	}
	elsif ( $response !~ /^\*/ ) {
		&Log ("unexpected response: $response");
		# print STDERR "Error: $response\n";
		return 0;
	}
   }

   &sendCommand ( $conn, "$rsn FETCH 1:* (uid flags internaldate body[header.fields (Message-Id)])");
   undef @response;
   while ( 1 ) {
	&readResponse ( $conn );
	if ( $response =~ /^$rsn OK/i ) {
		# print STDERR "response $response\n";
		last;
	}
	elsif ( $XDXDXD ) {
		&Log ("unexpected response: $response");
		&Log ("Unable to get list of messages in this mailbox");
		push(@errors,"Error getting list of $user's msgs");
		return 0;
	}
   }

   #  Get a list of the msgs in the mailbox
   #
   undef @msgs;
   undef $flags;
   for $i (0 .. $#response) {
	$seen=0;
	$_ = $response[$i];

	last if /OK FETCH complete/;

	if ( $response[$i] =~ /FETCH \(UID / ) {
	   $response[$i] =~ /\* ([^FETCH \(UID]*)/;
	   $msgnum = $1;
	}

	if ($response[$i] =~ /FLAGS/) {
	    #  Get the list of flags
	    $response[$i] =~ /FLAGS \(([^\)]*)/;
	    $flags = $1;
   	    $flags =~ s/\\Recent//i;
	}
        if ( $response[$i] =~ /INTERNALDATE ([^\)]*)/ ) {
	    ### $response[$i] =~ /INTERNALDATE (.+) ([^BODY]*)/i; 
	    $response[$i] =~ /INTERNALDATE (.+) BODY/i; 
            $date = $1;
            $date =~ s/"//g;
	}
	if ( $response[$i] =~ /^Message-Id:/ ) {
	    ($label,$msgid) = split(/: /, $response[$i]);
	    push (@$msgs,"$msgid||||||$mailbox||||||$msgnum||||||$flags||||||$date");
	}
   }
}


sub fetchMsg {

my $msgnum = shift;
my $mbx    = shift;
my $conn   = shift;
my $message;

   &Log("   Fetching msg $msgnum...") if $debug;
   ### &sendCommand ($conn, "$rsn SELECT \"$mbx\"");
   &sendCommand ($conn, "$rsn EXAMINE \"$mbx\"");
   while (1) {
        &readResponse ($conn);
	last if ( $response =~ /^$rsn OK/i );
   }

   &sendCommand( $conn, "$rsn FETCH $msgnum (rfc822)");
   while (1) {
	&readResponse ($conn);
	if ( $response =~ /^$rsn OK/i ) {
		$size = length($message);
		last;
	} 
	elsif ($response =~ /message number out of range/i) {
		&Log ("Error fetching uid $uid: out of range",2);
		$stat=0;
		last;
	}
	elsif ($response =~ /Bogus sequence in FETCH/i) {
		&Log ("Error fetching uid $uid: Bogus sequence in FETCH",2);
		$stat=0;
		last;
	}
	elsif ( $response =~ /message could not be processed/i ) {
		&Log("Message could not be processed, skipping it ($user,msgnum $msgnum,$destMbx)");
		push(@errors,"Message could not be processed, skipping it ($user,msgnum $msgnum,$destMbx)");
		$stat=0;
		last;
	}
	elsif 
	   ($response =~ /^\*\s+$msgnum\s+FETCH\s+\(.*RFC822\s+\{[0-9]+\}/i) {
		($len) = ($response =~ /^\*\s+$msgnum\s+FETCH\s+\(.*RFC822\s+\{([0-9]+)\}/i);
		$cc = 0;
		$message = "";
		while ( $cc < $len ) {
			$n = 0;
			$n = read ($conn, $segment, $len - $cc);
			if ( $n == 0 ) {
				&Log ("unable to read $len bytes");
				return 0;
			}
			$message .= $segment;
			$cc += $n;
		}
	}
   }

   return $message;

}


sub usage {

   print STDOUT "usage:\n";
   print STDOUT " imapsync -S sourceHost/sourceUser/sourcePassword\n";
   print STDOUT "          -D destHost/destUser/destPassword\n";
   print STDOUT "          -d debug\n";
   print STDOUT "          -L logfile\n";
   print STDOUT "          -m mailbox list (eg \"Inbox, Drafts, Notes\". Default is all mailboxes)\n";
   exit;

}

sub processArgs {

   if ( !getopts( "dS:D:L:m:h" ) ) {
      &usage();
   }

   ($sourceHost,$sourceUser,$sourcePwd) = split(/\//, $opt_S);
   ($destHost,  $destUser,  $destPwd)   = split(/\//, $opt_D);
   $mbxList = $opt_m;
   $logfile = $opt_L;
   $debug = 1 if $opt_d;

   &usage() if $opt_h;

}

sub findMsg {

my $conn  = shift;
my $msgid = shift;
my $mbx   = shift;
my $msgnum;

   &Log("   SELECT $mbx") if $debug;
   &sendCommand ( $conn, "1 SELECT \"$mbx\"");
   while (1) {
	&readResponse ($conn);
	last if $response =~ /^1 OK/;
   }

   &Log("   Search for $msgid") if $debug;
   &sendCommand ( $conn, "$rsn SEARCH header Message-Id \"$msgid\"");
   while (1) {
	&readResponse ($conn);
	if ( $response =~ /\* SEARCH /i ) {
	   ($dmy, $msgnum) = split(/\* SEARCH /i, $response);
	   ($msgnum) = split(/ /, $msgnum);
	}

	last if $response =~ /^1 OK/;
	last if $response =~ /complete/i;
   }

   return $msgnum;
}

sub deleteMsg {

my $conn  = shift;
my $msgid = shift;
my $mbx   = shift;
my $rc;

   $msgnum = &findMsg( $conn, $msgid, $mbx );
   &Log("   msgnum is $msgnum") if $debug;

   &sendCommand ( $conn, "1 STORE $msgnum +FLAGS (\\Deleted)");
   while (1) {
        &readResponse ($conn);
        if ( $response =~ /^1 OK/i ) {
	   $rc = 1;
	   &Log("   Marked $msgid for delete");
	   last;
	}

	if ( $response =~ /^1 BAD|^1 NO/i ) {
	   &Log("Error setting \Deleted flag for msg $msgnum: $response");
	   $rc = 0;
	   last;
	}
   }

   return $rc;

}

sub expungeMbx {

my $conn  = shift;
my $mbx   = shift;

   &Log("SELECT $mbx") if $debug;
   &sendCommand ( $conn, "1 SELECT \"$mbx\"");
   while (1) {
        &readResponse ($conn);
        last if $response =~ /^1 OK/;

	if ( $response =~ /^1 NO|^1 BAD/i ) {
	   &Log("Error selecting mailbox $mbx: $response");
	   last;
	}
   }

   &sendCommand ( $conn, "1 EXPUNGE");
   while (1) {
        &readResponse ($conn);
        last if $response =~ /^1 OK/;

	if ( $response =~ /^1 BAD|^1 NO/i ) {
	   print "Error expunging messages: $response\n";
	   last;
	}
   }

}

sub checkForAdds {

my $added=0;

   &Log("Checking for messages to add to $destHost/$destUser");
   foreach $key ( @sourcekeys ) {
        if ( $destList{"$key"} eq '' ) {
             $entry = $sourceList{"$key"};
             ($msgid,$mbx) = split(/\|\|\|\|\|\|/, $key);
             ($msgnum,$flags,$date) = split(/\|\|\|\|\|\|/, $entry);
             &Log("   Adding $msgid to $mbx");

             #  Need to add this message to the dest host

             $message = &fetchMsg( $msgnum, $mbx, 'SRC' );

             &insertMsg( 'DST', $mbx, *message, $flags, $date );
             $added++;
        }
   }
   return $added;

}


sub checkForUpdates {

my $updated=0;

   #  Compare the flags for the message on the source with the
   #  one on the dest.  Update the dest flags if they are different

   &Log("Checking for flag changes to $destHost/$destUser");
   foreach $key ( @sourcekeys ) {
        $entry = $sourceList{"$key"};
        ($msgid,$mbx) = split(/\|\|\|\|\|\|/, $key);
        ($msgnum,$srcflags,$date) = split(/\|\|\|\|\|\|/, $entry);

        if ( $destList{"$key"} ne '' ) {
             $entry = $destList{"$key"};
             ($msgid,$mbx) = split(/\|\|\|\|\|\|/, $key);
             ($msgnum,$dstflags,$date) = split(/\|\|\|\|\|\|/, $entry);

	     $srcflags  =~ s/\\Recent//i;
	     $destflags =~ s/\\Recent//i;
	     if ( $srcflags ne $dstflags ) {
		&Log("   Need to update the flags for $msgid") if $debug;
		$updated++ if &updateFlags( 'DST', $msgid, $mbx, $srcflags );
	     }
	}
   }
   return $updated;
}

sub checkForDeletes {

my $deleted=0;

   #  Find any messages in the dest which are not in the source
   #  and remove them from the dest

   &Log("Checking for messages to remove from $destHost/$destUser");
   foreach $key ( @destkeys) {
        if ( $sourceList{"$key"} eq '' ) {
           ($msgid, $mbx) = split(/\|\|\|\|\|\|/, $key);
           &Log("   Need to delete $msgid from $mbx") if $debug;

           if ( &deleteMsg( 'DST', $msgid, $mbx ) ) {
              #  Need to expunge messages from this mailbox when we're done
              $deleted++;
              push( @purgeMbxs, $mbx );
           }
        } 
   }

   #  Now purge the messages we set to \Deleted
   foreach $mbx ( @purgeMbxs ) {
        &expungeMbx( 'DST', $mbx );
   }

   return $deleted;

}

sub updateFlags {

my $conn  = shift;
my $msgid = shift;
my $mbx   = shift;
my $flags = shift;
my $rc;

   $msgnum = &findMsg( $conn, $msgid, $mbx );

   &sendCommand ( $conn, "1 STORE $msgnum +FLAGS ($flags)");
   while (1) {
        &readResponse ($conn);
        if ( $response =~ /^1 OK/i ) {
	   &Log("   Updated flags for $msgid");
	   $rc = 1;
	   last;
	}

        if ( $response =~ /^1 BAD|^1 NO/i ) {
           &Log("Error setting flags for $msgid: $response");
	   $rc = 0;
           last;
        }
   }
   return $rc;
}
