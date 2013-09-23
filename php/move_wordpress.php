<?php

// Simple Script to "move" wordpress to a new location.
// Enter database information, to and from URL's, and click go!  

if($_POST['actz'] == "move") {
	foreach($_POST as $varname => $value) {
		${$varname} = $value;
	}
	// Default Wordpress Prefix
	if($prefix == '') {
		$prefix = "wp_";
	}
	// Build Queries
	$options = "UPDATE ".$prefix."options SET option_value = replace(option_value, '$fromURL', '$toURL') WHERE option_name = 'home' OR option_name = 'siteurl';\n";
	$guid = "UPDATE ".$prefix."posts SET guid = REPLACE (guid, '$fromURL', '$toURL');\n";
	$postContent = "UPDATE ".$prefix."posts SET post_content = REPLACE (post_content, '$fromURL', '$toURL');\n";
	$addPostContent = "UPDATE ".$prefix."posts SET post_content = REPLACE (post_content, 'src=\"$fromURL', 'src=\"$toURL');\n";
	$postMeta = "UPDATE ".$prefix."postmeta SET meta_value = REPLACE (meta_value, '$fromURL','$toURL');\n";
	$cforms = "UPDATE ".$prefix."cformsdata SET field_val = REPLACE (field_val, '$fromURL', '$toURL') WHERE field_name = 'page';\n";
	$cformsSettings = "UPDATE ".$prefix."options SET option_value = REPLACE (option_value, '$fromURL', '$toURL') WHERE option_name = 'cforms_settings';\n";
	
	// Try Connect to DB
	$dbLink = mysql_connect('localhost', $dbuser, $dbpass);
	mysql_select_db($dbname);
	if(!$dbLink) {
		print "<h1>ERROR</h1>\n";
		print "<h3>Could Not Connect:</h3>\n";
		print mysql_error();	
		exit;
	}
	
	// Run Queries	
	print "<h1>Moving Wordpress</h1>\n";
	print "<b>Moving Options:</b> &nbsp;&nbsp;\n";
	// OPTIONS
	$result = mysql_query($options, $dbLink);
	if(!$result) {
		print "ERROR:".mysql_error();
		exit;
	} else {
		$number = mysql_affected_rows();
		print "$number rows changed<br />\n";
	}
	// GUID
	print "<b>Moving GUID:</b> &nbsp;&nbsp;\n";
        $result = mysql_query($guid, $dbLink);
        if(!$result) {
                print "ERROR:".mysql_error();
                exit;
        } else {
                $number = mysql_affected_rows();
                print "$number rows changed<br />\n";
        }
        // Content
	print "<b>Moving Content:</b> &nbsp;&nbsp;\n";
        $result = mysql_query($postContent, $dbLink);
        if(!$result) {
                print "ERROR:".mysql_error();
                exit;
        } else {
                $number = mysql_affected_rows();
                print "$number rows changed<br />\n";
        }
        // Additional Content
	print "<b>Moving Additional Content:</b> &nbsp;&nbsp;\n";
        $result = mysql_query($addPostContent, $dbLink);
        if(!$result) {
                print "ERROR:".mysql_error();
                exit;
        } else {
                $number = mysql_affected_rows();
                print "$number rows changed<br />\n";
        }
        // Post Meta
	print "<b>Moving Post Meta Data:</b> &nbsp;&nbsp;\n";
        $result = mysql_query($postMeta, $dbLink);
        if(!$result) {
                print "ERROR:".mysql_error();
                exit;
        } else { $number = mysql_affected_rows();
                print "$number rows changed<br />\n";
        }

        // CForms 
        print "<b>Moving CForms Data:</b> &nbsp;&nbsp;\n";
        $result = mysql_query($cforms, $dbLink);
        if(!$result) {
                print "ERROR:".mysql_error();
                exit;
        } else {
                $number = mysql_affected_rows();
                print "$number rows changed<br />\n";
        }

        // CForms Settings
        print "<b>Moving CForms Settings:</b> &nbsp;&nbsp;\n";
        $result = mysql_query($cformsSettings, $dbLink);
        if(!$result) {
                print "ERROR:".mysql_error();
                exit;
        } else {
                $number = mysql_affected_rows();
                print "$number rows changed<br />\n";
        }


	print "<h3>COMPLETE</h3>\n";
	exit;

}
?>

<html>
 <head>
 <title>Wordpress Mover</title>
 </head>
 <body>
 <h1>Move Your Wordpress Site!</h1>
 <form name="info" method="POST" action="<?php echo($_SERVER['PHP_SELF']); ?>">
  <input type="hidden" name="actz" value="move">
  <h3>Database Info</h3>
	<b>Database Name:</b> <input type="text" name="dbname" size="30"><br />
	<b>Database User:</b> <input type="text" name="dbuser" size="30"><br />
	<b>Database Password:</b> <input type="password1" name="dbpass" size="30"><br />
  <h3>Wordpress Info</h3>
	<b>Current (Existing) URL:</b> <input type="text" name="fromURL" size="30"><br />
	<b>New Location URL:</b> <input type="text" name="toURL" size="30"><br />
	<b>Table Prefix:</b> <input type="text" name="prefix" size="10" value="wp_"><br />
	<br />
	<input type="submit" value="Move It!" name="move">
 </form>
 </body>
</html>
