#!/usr/local/bin/perl

###############################################################################
# Set up all needed modules and objects
###############################################################################
use strict;
use Getopt::Long;
use FindBin;

use lib qw (../lib/perl ../../lib/perl);

use vars qw ($sbeams $sbeamsMOD $q $dbh $current_contact_id $current_username
             $PROG_NAME $USAGE %OPTIONS $QUIET $VERBOSE $DEBUG $DATABASE
             $sbeams_affy_groups);
#use CGI;
use CGI::Carp qw(fatalsToBrowser croak);

use SBEAMS::Connection qw($q $log);
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::Tables;
use SBEAMS::Connection::TableInfo;
#$q = new CGI;
$sbeams = new SBEAMS::Connection;

use SBEAMS::Microarray;
use SBEAMS::Microarray::Settings;
use SBEAMS::Microarray::Tables;
use SBEAMS::Microarray::TableInfo;

use SBEAMS::Microarray::Affy;
use SBEAMS::Microarray::Affy_file_groups;

$sbeamsMOD = new SBEAMS::Microarray;

$sbeamsMOD->setSBEAMS($sbeams);
$sbeams->setSBEAMS_SUBDIR($SBEAMS_SUBDIR);

$sbeams_affy_groups = new SBEAMS::Microarray::Affy_file_groups;
$sbeams_affy_groups->setSBEAMS($sbeams);
###############################################################################
# Set program name and usage banner for command like use
###############################################################################
$PROG_NAME = $FindBin::Script;
$USAGE = <<EOU;
Usage: $PROG_NAME 
Options:
  --verbose n         Set verbosity level.  default is 0
  --quiet             Set flag to print nothing at all except errors
  --debug n           Set debug flag

 e.g.:  $PROG_NAME [OPTIONS] [keyword=value],...

EOU

#### Process options
unless (GetOptions(\%OPTIONS,"verbose:s","quiet","debug:s")) {
  print "$USAGE";
  exit;
}

$VERBOSE = $OPTIONS{"verbose"} || 0;
$QUIET = $OPTIONS{"quiet"} || 0;
$DEBUG = $OPTIONS{"debug"} || 0;
if ($DEBUG) {
  print "Options settings:\n";
  print "  VERBOSE = $VERBOSE\n";
  print "  QUIET = $QUIET\n";
  print "  DEBUG = $DEBUG\n";
}



###############################################################################
# Set Global Variables and execute main()
###############################################################################
	
my $FILE_BASE_DIR = $sbeamsMOD->get_AFFY_DEFAULT_DIR();
my $DOC_BASE_DIR = "";
my $DATA_READER_ID = 40;

main();
exit(0);



###############################################################################
# Main Program:
#
# Call $sbeams->InterfaceEntry with pointer to the subroutine to execute if
# the authentication succeeds.
###############################################################################
sub main {

  #### Do the SBEAMS authentication and exit if a username is not returned
  exit unless ($current_username = $sbeams->Authenticate(
    #connect_read_only=>1,
    #allow_anonymous_access=>1,
    #permitted_work_groups_ref=>['Proteomics_user','Proteomics_admin'],
  ));

  #### Read in the default input parameters
  my %parameters;
  my $n_params_found = $sbeams->parse_input_parameters(
    q=>$q,parameters_ref=>\%parameters);
  #$sbeams->printDebuggingInfo($q);

  #### Define standard variables
  my $affy_array_id = $parameters{'affy_array_id'};
  my $analysis_folder = $parameters{'analysis_folder'};
  my $analysis_file = $parameters{'analysis_file'};

  my $annotated_file = $parameters{'annotated_file'};
  
 unless ( $affy_array_id || ($analysis_folder && $analysis_file) ||$annotated_file) {
 	 die "ERROR: Need to Pass affy_array_id or analysis_folder &  $analysis_file ";
 }
	my $action = $parameters{'action'} || "download";
	
	my $file_ext      = $parameters{'file_ext'};
	my $project_id = $sbeams->getCurrent_project_id;

	my $output_dir ='';
	my $file_name = '';
	if ($affy_array_id) {
		($file_name, $output_dir) = $sbeams_affy_groups->get_file_path_from_id(affy_array_id => $affy_array_id);  #return the file_root_name and file_base_path
	}elsif($analysis_folder){
		$output_dir = $sbeamsMOD->affy_bioconductor_delivery_path();
		$output_dir .= "/$analysis_folder";
		$file_name = $analysis_file;
	}elsif($annotated_file){
		$output_dir = $sbeamsMOD->get_ANNOTATION_OUT_FOLDER();
		$file_name = $annotated_file;
	}
	
	#### Verify user has permission to access the file
	error("You do not have sufficent privillages to view data within this project") 
	unless ($sbeams->get_best_permission <= $DATA_READER_ID);
	
	error("You are not allowed to view ANY data from this project") 
	unless (grep {$project_id == $_} $sbeams->getAccessibleProjects);

	
	if ($action eq 'download') {
	    
	    
		print "Content-type: application/force-download \n";
		print "Content-Disposition: filename=$file_name.$file_ext\n\n";
		my $buffer;
		open (DATA, "$output_dir/$file_name.$file_ext")
		    || die "Couldn't open $file_name.$file_ext";
		while(read(DATA, $buffer, 1024)) {
		    print $buffer;
		}
		close (DATA);
	    
	}elsif ($action eq 'view_image'){
		my $file;
		my $subdir = $parameters{'SUBDIR'};
		if ($subdir){$file = "$output_dir/$subdir/$file_name";}
		else{$file = "$output_dir/$file_name.$file_ext";}
		linkImage(file=>$file);
	}else {
	  #### Start printing the page
	  $sbeamsMOD->printPageHeader();	
	  # print "INFO $output_dir/$file_name.$file_ext'<br>";

    # This block of code removes the pbs job out/err file if it exists.  This
    # will keep us from accreting these files, which are unused anyway.  If this
    # block fails at a remote site it is likely that the permissions on the 
    # job dir are flawed.
    if ( -e "${output_dir}/pbs_job.out" ) {
      $log->info( "Removing pbs_job output file" );
      unlink( "${output_dir}/pbs_job.out" );
    }
	   
		my $file = "$output_dir/$file_name.$file_ext";
		printFile(file		=>$file,
				  file_ext 	=>$file_ext);
	    
	    $sbeamsMOD->printPageFooter();
	}
} # end main




###############################################################################
# linkImage
#
###############################################################################
sub linkImage {
  my %args = @_;
  my $file = $args{'file'};
  my $error = 0;
  open(INFILE, "< $file") || sub{$error = -1;};

  if ($error == 0) {
			print "Content-type: image/jpeg\n\tname=\"file.jpg\"";
			print "Content-Transfer-Encoding: base64\n";
			print "Content-Disposition: inline\n";
			print "\n";

			my $buffer;
			open (IMAGE, "$file") || die "Couldn't open $file";
			binmode(IMAGE);
			while(read(IMAGE,$buffer,1024)){
				print $buffer;
			}
  }
  else{
    my $mailto = $sbeams->get_admin_mailto('administrator');
    print qq~
	  $file
	  <CENTER><FONT COLOR="red"><h1><B>FILE COULD NOT BE OPENED FOR VIEWING</B></h1>
	  Please report this to $mailto
	  </FONT></CENTER>
     ~;
  }
	  
} # end printFile

###############################################################################
# printFile
#
# A very simple script.  Throw the contents of the file within <PRE> tags and
# we're done
###############################################################################
sub printFile {
  my %args = @_;

  my $file = $args{'file'};
  my $file_ext = $args{file_ext};
  
  my $error = 0;

  open(INFILE, "< $file") || sub{ $error++; };
  my $all_data;
  if ( $error ) {
    my $mailto = $sbeams->get_admin_mailto('administrator');
    print qq~
	  $file
	  <CENTER><FONT COLOR="red"><h1><B>FILE COULD NOT BE OPENED FOR VIEWING</B></h1>
	  Please report this to the SBEAMS $mailto.
	  </FONT></CENTER>
    ~;

  } else {
    print "<PRE>\n" if $file_ext ne 'html';
    while(<INFILE>){ 
    # The following line was put in to remove a mysterious '<b>' tag
#      $_ =~ s/\<[^>]+?\>//g if $file_ext ne 'html';
      print $_;
    }
    print "</PRE>\n" if $file_ext ne 'html';
  }
	  
} # end printFile

sub error{
	my $error_info = shift;
	$sbeams->printPageHeader();
		print qq~
		    <BR><BR><BR>
		    <H1><FONT COLOR="red">You Do Not Have Access To View This File</FONT></H1>
		    <H2><FONT COLOR="red">Reason: $error_info</FONT></H2>
		    ~;
		$sbeamsMOD->printPageFooter();
	exit;
}
