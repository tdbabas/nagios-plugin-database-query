.. highlight:: perl


****
NAME
****


check_db_query.pl - Runs query specified in an external file and checks the result against the specified thresholds.


********
SYNOPSIS
********


\ **check_db_query.pl**\  \ **-d**\  \ *database*\  \ **-q**\  \ *query*\  [\ **-w**\  \ *warn*\ ] [\ **-c**\  \ *crit*\ ] [\ **-C**\  \ *conn_file*\ ] [\ **-p**\  \ *placeholder*\ ]


***********
DESCRIPTION
***********


\ **check_db_query.pl**\  will run a query specified in \ *query*\  in the database specified by \ *database*\ . These values are
configured in the connection file specified in \ *conn_file*\ .


************
REQUIREMENTS
************


The following Perl modules are required in order for this script to work:


.. code-block:: perl

  * DBI
  * Nagios::Plugin
  * File::Basename
  * Scalar::Util
  * XML::Simple


Additionally, you will need any DBD modules required to access your databases need to be installed and setup correctly.

A connection file also needs to be present. By default, the script will use a file called \ **.db_conn.xml**\ , which it expects to
find in the same directory as the script. If you want to use a different file, you must specify it with the \ **-C**\  option.


*******
OPTIONS
*******


\ **-d**\  \ *database*\ 

The name of the database to run the script against. This database must be specified in the connection file.

\ **-q**\  \ *query*\ 

The query to run. This also must be specified in the connection file. The query must be a SELECT query, otherwise an error will
be generated. The resulting output from this query will be compared against the specified thresholds to produce the status of
this check. The script will only compare the result of the first column of the first row returned. All other data will be discarded.
If the result of the query is NULL or not numeric, then the script will interpret this as "undef".

\ **-w**\  \ *warn*\ 

The warning threshold. See https://nagios-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the expected format of the threshold.
If not specified, it is set to 0.

\ **-c**\  \ *crit*\ 

The critical threshold. See https://nagios-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the expected format of the threshold.
If not specified, it is set to 0.

\ **-C**\  \ *conn_file*\ 

Uses \ *conn_file*\  as the connection file, as opposed to the default (./.db_conn.xml).

\ **-p**\  \ *placeholder*\ 

Values to substitute the placeholder values with. There must be one \ **-p**\  \ *placeholder*\  option for each placeholder variable in the
query, otherwise, the script will generate an error.


*****************************
CONNECTION FILE SPECIFICATION
*****************************


The connection file is an XML file, and contains all the details of the databases and queries you want to use with this script. Because
the file contains usernames and passwords in plain text, you will probably want to hide the file and alter the permissions accordingly.
However, the Nagios user must be able to read the file in order for the script to work. Below is an example of an entry in the connection
file and what the tags mean:


.. code-block:: perl

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


<xml>
=====


The configuration should be enclosed within \ **<xml>**\  tags.


<database>
==========


Each database you will want to connect to should have a \ **<database>**\  section. The \ **id**\  attribute is a unique name 
associated with this database, which can then be referred to in the script by using the \ **-d**\  option.


<dbd>
=====


This is the Perl database driver to be used to connect to this database.


<values>
========


These are additional connection values that are required to connect to the database. Using these, and the <dbd>, the script
will create the data source name (DSN) which will be used to connect to the required database.


<value>
=======


A key/value entry to be used in the DSN. So, for the example above, the data source name will be "DBI:mysql:database=test;host=localhost".


<username>
==========


The username to connect to the database as.


<password>
==========


The password for this user. Note that if a username or password is not required, the tags still have to be present. For some databases,
a blank password would be specified in this file as <password>""</password>.


<queries>
=========


The list of queries that can be run in this database.


<sql>
=====


The SQL for the particular query. The query is identified by the \ **id**\  attribute, which is then referred to in the script by using the \ **-q**\ 
option. Note that XML cannot parse less than (<) or greater than (>) signs, so if you need them in your query code, you will either
have to encode them as &lt; and &gt; respectively or enclose the query code in <![CDATA[ ]]> tags. Placeholder/bind variables should
be specified with question-marks (?), which will be filled by using the \ **-p**\  option when running the script.



*******
EXAMPLE
*******


./check_db_query.pl -d TestDB -q test -w 200: -c 100:

Runs the query specified in the example above and produces a WARNING state if the return value is less than 200 or a CRITICAL state if the return 
value is less than 100.


*************
USE IN NAGIOS
*************


When using this script in Nagios, if you are using the default connection file, you may have to specify the full path to your Perl binary
in your command definition. For example:


.. code-block:: perl

  define command{
          command_name    check_db_entries
          command_line    /usr/local/bin/perl $USER1$/check_db_query.pl -d "$ARG1$" -q "$ARG2$" $ARG3$
  }



***************
ACKNOWLEDGEMENT
***************


This documentation is available as POD and reStructuredText, with the conversion from POD to RST being carried out by \ **pod2rst**\ , which is 
available at http://search.cpan.org/~dowens/Pod-POM-View-Restructured-0.02/bin/pod2rst


******
AUTHOR
******


Tim Barnes <tdba[AT]bas[DOT]ac[DOT]uk> - British Antarctic Survey, Natural Environmental Research Council, UK


*********************
COPYRIGHT AND LICENSE
*********************


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

