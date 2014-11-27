#!/usr/local/bin/perl -w

################################################################################
# check_db_query.pl 
#
# Runs query specified in an external file and checks the result against the
# specified thresholds.
#
# TDBA 2014-11-24 - First version
################################################################################
# GLOBAL DECLARATIONS
################################################################################
use warnings;
use strict;
use DBI;
use Nagios::Plugin;
use File::Basename;
use Scalar::Util qw(looks_like_number);
use XML::Simple;

# Set default values and version number
my $VERSION       = "1.0.0 [2014-11-24]"; # Version number
my $DIRNAME       = dirname($0);          # Directory where this script is run from
my $SHORT_NAME    = "DB QUERY";           # Short name for this script
my $DEF_CONN_FILE = sprintf("%s/%s", $DIRNAME, ".db_conn.xml"); # Database connection file
my $DEF_WARN      = 0; # Default warning threshold
my $DEF_CRIT      = 0; # Default critical threshold
################################################################################
# MAIN BODY
################################################################################

# Create the usage message
my $usage_msg = qq(Usage: %s -d <database> -q <query> [-w <warn> -c <crit> -C <conn_file>] [-p <placeholder>]

<database> and <query> must be specified in <conn_file>. See the perldoc for this plugin 
for more details. <warn> and <crit> should be specified according to the standard Nagios 
threshold format. You can specify as many \"-p <placeholder>\" expressions as you want, 
provided that your desired query contains that many placeholder variables);

# Create the Nagios plugin
my $nagios = Nagios::Plugin->new(shortname => $SHORT_NAME, usage => $usage_msg, version => $VERSION);

# Add command line arguments
$nagios->add_arg("d=s",  "-d <database>\n   Name of database (as specified in the connection file)", undef, 1);
$nagios->add_arg("q=s",  "-q <query>\n   Name of query (as specified in the connection file)", undef, 1);
$nagios->add_arg("w=s",  "-w <warn>\n   Warning threshold (default: $DEF_WARN)",  $DEF_WARN, 1);
$nagios->add_arg("c=s",  "-c <crit>\n   Critical threshold (default: $DEF_CRIT)", $DEF_CRIT, 1);
$nagios->add_arg("C=s",  "-C <conn_file>\n   DB connection file (default: $DEF_CONN_FILE)", $DEF_CONN_FILE, 0);
$nagios->add_arg("p=s@", "-p <placeholder>\n   Specify a value to replace a placeholder variable with", [], 0);

# Parse command line arguments
$nagios->getopts;

# Set variables
my $db_name      = $nagios->opts->d;
my $query_id     = $nagios->opts->q;
my $conn_file    = $nagios->opts->C;
my $placeholders = $nagios->opts->p;

# Get required database query from the connection file
my ($db_info, $sql) = parse_connection_file($nagios, $conn_file, $db_name, $query_id);

# Check we have database info and a query. If not, display CRITICAL message
if (!keys(%$db_info)) 
{ 
   $nagios->nagios_exit(2, sprintf("Cannot find connection information for database '%s' in '%s'!\n", $db_name, $conn_file)); 
}
if (!$sql) 
{ 
   $nagios->nagios_exit(2, sprintf("Cannot find query with ID '%s' in database '%s' in '%s'!\n", $query_id, $db_name, $conn_file)); 
}

# We only want to do SELECT queries. Anything else could potentially alter the database, and we don't want to do that here!
# So, check that query begins with "SELECT...". If not, then quit
if ($sql !~ m/^(\s)*select/i)
{
   $nagios->nagios_exit(2, sprintf("Query '%s' is not a SELECT query!\n", $query_id));
}

# Set the thresholds
$nagios->set_thresholds(warning => $nagios->opts->w, critical => $nagios->opts->c);

# Connect to database
my $conn = connect_to_db($nagios, $db_name, $db_info);

# Run the query and get the result
my $result = run_query($nagios, $conn, $sql, $placeholders);

# Disconnect from database
disconnect_from_db($conn);

# If value is defined, check the value falls within the threshold and return appropriate value
# Otherwise, set the status to CRITICAL
my $status = 0;
if (defined($result))
{
   $status = $nagios->check_threshold($result);

   # Set the performance data
   $nagios->add_perfdata(label => "result", value => $result, threshold => $nagios->threshold());
}
else
{
   $status = 2;
   $result = "undefined";
}

# Exit from Nagios
$nagios->nagios_exit($status, sprintf("Result from query is %s", $result));
################################################################################
# SUBROUTINES
################################################################################
sub parse_connection_file # Parses an XML database connection file and stores the information as hashes
{
    my ($n, $conn_file, $db_name, $query) = @_;

    # Check config file exists. If it doesn't display error and quit
    if (! -e $conn_file) { $n->nagios_exit(2, sprintf("Connection file '%s' does not exist!\n", $conn_file)); }

    # Read in the config file
    my $xml = XMLin($conn_file, ForceArray => 1);

    # Setup the info hash and the query variable
    my ($db_info, $sql) = ({}, "");

    # Get the database information
    while (my ($id, $this_db) = each(%{${$xml}{'database'}}))
    {
       # If this database does not match the desired one, skip
       if ($id ne $db_name) { next; }
       
       # Add the information to the hash
       ${$db_info}{'id'}   = $id;
       ${$db_info}{'type'} = ${$this_db}{'dbd'}[0];
       ${$db_info}{'user'} = ${$this_db}{'username'}[0];
       ${$db_info}{'pass'} = (ref(${$this_db}{'password'}[0]) eq "HASH") ? "" : ${$this_db}{'password'}[0];

       # Add the key/value pairs
       ${$db_info}{'values'} = ();
       while (my ($k, $v) = each(%{${$this_db}{'values'}[0]{'value'}}))
       {
          ${$db_info}{'values'}{$k} = ${$v}{'content'};
       } 

       # Go through the queries and find the desired one
       if (${$this_db}{'queries'})
       {
          my $q = ${$this_db}{'queries'}[0];
          while (my ($qid, $this_query) = each(%{${$q}{'sql'}}))
          {
             # If this query doesn't match the desired one, skip
             if ($qid ne $query) { next; }

             # Extract the SQL from the content
             $sql = ${$this_query}{'content'};

             # We have what we want, so stop processing
             last;
          }
       }

       # We have what we want, so stop processing
       last;
    }

    # Return the database info hash and the query
    return ($db_info, $sql);
}
################################################################################
sub connect_to_db # Connects to DB
{
    my ($n, $id, $db_hash) = @_;

    # Check the required elements are in the DB hash
    if (!defined(${$db_hash}{'type'})) { $n->nagios_exit(2, sprintf("No database type specified for '%s'!\n", $id)); }
    if (!defined(${$db_hash}{'user'})) { $n->nagios_exit(2, sprintf("No username specified for '%s'!\n",      $id)); }
    if (!defined(${$db_hash}{'pass'})) { $n->nagios_exit(2, sprintf("No password specified for '%s'!\n",      $id)); }

    # Create the data source name
    my @strparts = ();
    while (my($k, $v) = each(%{${$db_hash}{'values'}}))
    {
       push(@strparts, sprintf("%s=%s", $k, $v));
    }
    my $str = (scalar(@strparts) == 0) ? "" : ":" . join(";", @strparts);
    my $dsn = sprintf("DBI:%s%s", ${$db_hash}{'type'}, $str);

    # Connect to the database
    my $conn = DBI->connect($dsn, ${$db_hash}{'user'}, ${$db_hash}{'pass'}, {'RaiseError' => 1, 'PrintError' => 0, 'AutoCommit' => 0});

    # If we cannot connect, display an error
    if (!$conn) { $n->nagios_exit(2, sprintf("Failed to connect to database '%s': %s\n", $id, $DBI::errstr)); }

    # Return the handle
    return $conn;
}
################################################################################
sub disconnect_from_db # Disconnects from DB
{
    my ($conn) = @_;

    $conn->disconnect();
}
################################################################################
sub run_query # Runs a query
{
    my $n    = (defined($_[0])) ? $_[0] : "";
    my $conn = (defined($_[1])) ? $_[1] : "";
    my $sql  = (defined($_[2])) ? $_[2] : ""; 
    my $vars = (defined($_[3])) ? $_[3] : []; 

    # First, test if we have a database connection. If not, display error and quit
    if (!$conn) { $n->nagios_exit(2, "No database connection!"); }

    # Parse the query, or error if there is a problem
    my $sth = $conn->prepare($sql);
    if (!$sth) 
    { 
       disconnect_from_db($conn);
       $n->nagios_exit(2, sprintf("Error in preparing query!: %s\n", $conn->errstr)); 
    }

    # Add bind variables, if required
    for (my $i=1; $i<=scalar(@$vars); $i++) { $sth->bind_param($i, ${$vars}[$i - 1]); }

    # Execute query and quit if there is an error
    my $exec = $sth->execute();
    if (!$exec)
    {
       my $err_msg = sprintf("Error in executing query!: %s\n", $sth->errstr);
       disconnect_from_db($conn);
       $n->nagios_exit(2, $err_msg);
    }

    # Get the result
    my $result = 0;
    while (my @row = $sth->fetchrow_array()) 
    { 
       $result = looks_like_number($row[0]) ? $row[0] : undef;
    }
   
    # Return the result
    return $result;
}
################################################################################
# DOCUMENTATION
################################################################################

=head1 NAME

check_db_query.pl - Runs query specified in an external file and checks the result against the specified thresholds.

=head1 SYNOPSIS

B<check_db_query.pl> B<-d> I<database> B<-q> I<query> [B<-w> I<warn>] [B<-c> I<crit>] [B<-C> I<conn_file>] [B<-p> I<placeholder>]

=head1 DESCRIPTION

B<check_db_query.pl> will run a query specified in I<query> in the database specified by I<database>. These values are
configured in the connection file specified in I<conn_file>.

=head1 REQUIREMENTS

The following Perl modules are required in order for this script to work:

 * DBI
 * Nagios::Plugin
 * File::Basename
 * Scalar::Util
 * XML::Simple

Additionally, any DBD modules required to access your databases need to be installed and setup correctly.

A connection file also needs to be present. By default, the script will use a file called B<.db_conn.xml>, which it expects to
find in the same directory as the script. If you want to use a different file, you must specify it with the B<-C> option.

=head1 OPTIONS

B<-d> I<database>

The name of the database to run the script against. This database must be specified in the connection file.

B<-q> I<query>

The query to run. This also must be specified in the connection file. The query must be a SELECT query, otherwise an error will
be generated. The resulting output from this query will be compared against the specified thresholds to produce the status of
this check. The script will only compare the result of the first column of the first row returned. All other data will be discarded.
If the result of the query is NULL or not numeric, then the script will interpret this as "undef".

B<-w> I<warn>

The warning threshold. See https://nagios-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the expected format of the threshold.
If not specified, it is set to 0.

B<-c> I<crit>

The critical threshold. See https://nagios-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the expected format of the threshold.
If not specified, it is set to 0.

B<-C> I<conn_file>

Uses I<conn_file> as the connection file, as opposed to the default (./.db_conn.xml). 

B<-p> I<placeholder>

Values to substitute the placeholder values with. There must be one B<-p> I<placeholder> option for each placeholder variable in the
query, otherwise, the script will generate an error.

=head1 CONNECTION FILE SPECIFICATION

The connection file is an XML file, and contains all the details of the databases and queries you want to use with this script. Because
the file contains usernames and passwords in plain text, you will probably want to hide the file and alter the permissions accordingly.
However, the Nagios user must be able to read the file in order for the script to work. Below is an example of an entry in the connection
file and what the tags mean:

 <xml>
    <database id='TestDB'>
       <dbd>mysql</dbd>
       <values>
          <value key='host'>localhost</value>
          <value key='database'>test</value>
       </values>
       <username>test</username>
       <password></password>
       <queries>
          <sql id='test'>SELECT COUNT(*) FROM test_data</sql>
       </queries>
    </database>
 </xml>

=head2 E<lt>xmlE<gt>

The configuration should be enclosed within B<E<lt>xmlE<gt>> tags.

=head2 E<lt>databaseE<gt>

Each database you will want to connect to should have a B<E<lt>databaseE<gt>> section. The B<id> attribute is a unique name 
associated with this database, which can then be referred to in the script by using the B<-d> option.

=head2 E<lt>dbdE<gt>

This is the Perl database driver to be used to connect to this database.

=head2 E<lt>valuesE<gt>

These are additional connection values that are required to connect to the database. Using these, and the E<lt>dbdE<gt>, the script
will create the data source name (DSN) which will be used to connect to the required database.

=head2 E<lt>valueE<gt>

A key/value entry to be used in the DSN. So, for the example above, the data source name will be "DBI:mysql:database=test;host=localhost".

=head2 E<lt>usernameE<gt>

The username to connect to the database as.

=head2 E<lt>passwordE<gt>

The password for this user. Note that if a username or password is not required, the tags still have to be present. For some databases,
a blank password would be specified in this file as E<lt>passwordE<gt>""E<lt>/passwordE<gt>.

=head2 E<lt>queriesE<gt>

The list of queries that can be run in this database. 

=head2 E<lt>sqlE<gt>

The SQL for the particular query. The query is identified by the B<id> attribute, which is then referred to in the script by using the 
B<-q> option. Note that XML cannot parse less than (E<lt>) or greater than (E<gt>) signs, so if you need them in your query code, you 
will either have to encode them as &lt; and &gt; respectively or enclose the query code in E<lt>![CDATA[ ]]E<gt> tags. Placeholder/bind 
variables should be specified with question-marks (?), which will be filled by using the B<-p> option when running the script.

=head1 EXAMPLE

./check_db_query.pl -d TestDB -q test -w 200: -c 100:

Runs the query specified in the example above and produces a WARNING state if the return value is less than 200 or a CRITICAL state if the return 
value is less than 100.

=head1 USE IN NAGIOS

When using this script in Nagios, if you are using the default connection file, you may have to specify the full path to your Perl binary
in your command definition. For example:

 define command{
         command_name    check_db_entries
         command_line    /usr/local/bin/perl $USER1$/check_db_query.pl -d "$ARG1$" -q "$ARG2$" $ARG3$
 }

=head1 ACKNOWLEDGEMENT

This documentation is available as POD and reStructuredText, with the conversion from POD to RST being carried out by B<pod2rst>, which is 
available at http://search.cpan.org/~dowens/Pod-POM-View-Restructured-0.02/bin/pod2rst

=head1 NOTES

So far, this script has been tested with MySQL, Postgres, Oracle and SQLite2. Other database systems may work, but they have not been
tested as yet.

=head1 AUTHOR

Tim Barnes E<lt>tdba[AT]bas.ac.ukE<gt> - British Antarctic Survey, Natural Environmental Research Council, UK

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 by Tim Barnes, British Antarctic Survey, Natural Environmental Research Council, UK

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut
