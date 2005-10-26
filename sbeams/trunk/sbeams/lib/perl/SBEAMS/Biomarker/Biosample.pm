package SBEAMS::Biomarker::Biosample;

###############################################################################
#
# Description :   Library code for inserting biosource/biosample records into 
# the database
# $Id$
#
# Copywrite 2005   
#
###############################################################################

use strict;

use SBEAMS::Connection qw( $log );
use SBEAMS::Biomarker::Tables;     
use SBEAMS::Connection::Tables;     
 
#### Set up new variables
#use vars qw(@ISA @EXPORT);
#require Exporter;
#@ISA = qw (Exporter);
#@EXPORT = qw ();

sub new {
  my $class = shift;
	my $this = { @_ };
	bless $this, $class;
	return $this;
}

#+
# Method to check for existance of specified Attribute
#-
sub attrExists {
  my $this = shift;
  my $attr = shift;
  return unless $attr;

  my $sbeams = $this->getSBEAMS() || die "sbeams object not set";
  die "unsafe attr detected: $attr\n" if $sbeams->isTaintedSQL($attr);

  my ($cnt) = $sbeams->selectrow_array( <<"  END_SQL" );
  SELECT COUNT(*) FROM $TBBM_ATTRIBUTE
  WHERE attribute_name = '$attr'
  END_SQL

  return $cnt;
}   

####
#+
# Method for creating new biosample.
#-
sub add_new {
  my $this = shift;
  my %args = @_;

  for ( qw( data_ref group_id src_id  ) ) {
    die "Missing parameter $_" unless defined $_;    
  }

  my $sbeams = $this->getSBEAMS() || die "sbeams object not set";
  my $name = $args{data_ref}->{biosample_name} || die "no biosample name!";
  $args{data_ref}->{biosource_id} = $args{src_id};
  $args{data_ref}->{biosample_group_id} = $args{group_id};
  $args{data_ref}->{biosample_type_id} ||= ( $this->get_sample_type_id('source') ) ?
              $this->get_sample_type_id('source') : $this->add_source_type();



  # Sanity check 
  my ($is_there) = $sbeams->selectrow_array( <<"  END_SQL" );
  SELECT COUNT(*) FROM $TBBM_BIOSAMPLE
  WHERE biosample_name = '$name'
  END_SQL

  if( $is_there ) {
    print STDERR "Skipping biosample creation, entry exists: $name\n";
    next;
  }

   my $id = $sbeams->updateOrInsertRow( insert => 1,
                                     return_PK => 1,
                                    table_name => $TBBM_BIOSAMPLE,
                                   rowdata_ref => $args{data_ref},
                          add_audit_parameters => 1
                                    );

   $log->error( "Couldn't create biosample record" ) unless $id;
   return $id;

} # End add_new   


#+
#
#-
sub add_biosample_attrs {
  my $this = shift;
  my %args = @_;
   
  for ( qw( attrs smpl_id ) ) {
    die "Missing parameter $_" unless defined $_;    
  }

  my $sbeams = $this->getSBEAMS() || die "sbeams object not set";
   
  my %attr_hash = $sbeams->selectTwoColumnHash( <<"  END" );
  SELECT attribute_name, attribute_id FROM $TBBM_ATTRIBUTE
  END
   
  for my $key (keys(%{$args{attrs}})) {

    my $dataref = { biosample_id => $args{smpl_id},
                    attribute_id => $attr_hash{$key},
                    attribute_value => $args{attr}->{$key} };

    my $id = $sbeams->updateOrInsertRow( insert => 1,
                                      return_PK => 1,
                                   table_name => $TBBM_BIOSAMPLE_ATTRIBUTE,
                                    rowdata_ref => $dataref, 
                           add_audit_parameters => 0
                                       );

    $log->error( "Couldn't create biosample record" ) unless $id;
  }

} # End add_biosample_attrs   

####

#+
# Method to check for existance of specified storage_location
#-
sub storageLocExists {
  my $this = shift;
  my $stor = shift;
  return '' unless $stor;

  my $sbeams = $this->getSBEAMS() || die "sbeams object not set";
  die "unsafe storage location: $stor\n" if $sbeams->isTaintedSQL($stor);

  my ($cnt) = $sbeams->selectrow_array( <<"  END_SQL" );
  SELECT COUNT(*) FROM $TBBM_STORAGE_LOCATION
  WHERE location_name = '$stor'
  END_SQL

  return $cnt;
}   


#+
# Method for creating storage_location records.
# narg strg_loc, ref to array of storage_locations to add
# narg auto, default 0
#-
sub createStorageLoc {
  my $this = shift;
  my %args = @_;
  return unless $args{strg_loc};

  $args{auto} ||= 0;

  my $sbeams = $this->getSBEAMS() || die "sbeams object not set";

  foreach my $strg_loc ( @{$args{strg_loc}} ) {
    die "unsafe name detected: $strg_loc\n" if $sbeams->isTaintedSQL($strg_loc);
    $log->info("Creating storage location: $strg_loc");

    # Sanity check 
    my ($is_there) = $sbeams->selectrow_array( <<"    END_SQL" );
    SELECT COUNT(*) FROM $TBBM_STORAGE_LOCATION
    WHERE location_name = '$strg_loc'
    END_SQL

    next if $is_there;

    my $id = $sbeams->updateOrInsertRow( insert => 1,
                                      return_PK => 1,
                                     table_name => $TBBM_STORAGE_LOCATION,
                           add_audit_parameters => 1,
                                    rowdata_ref => {location_name => $strg_loc,
                        location_description => 'autogenerated, please update'},
                           add_audit_parameters => 1
                                     );

    $log->error( "Couldn't create storage location $strg_loc" ) unless $id;
  }
}

  
sub setSBEAMS {
  my $this = shift;
  my $sbeams = shift || die "Must pass sbeams object";
  $this->{_sbeams} = $sbeams;
}

sub getSBEAMS {
  my $this = shift;
  return $this->{_sbeams};
}

sub add_source_type {
  my $this = shift;
  # if it exists, return it, else create it
  print "calling with $this\n";
  my $id = $this->get_sample_type_id( 'source' );
  print "called with source\n";
  return $id if $id;

  my $rd = { biosample_type_name => 'source',
             biosample_type_description => 'New sample direct from biosource' };

  $this->getSBEAMS()->updateOrInsertRow( insert => 1,
                                      return_PK => 1,
                                     table_name => $TBBM_BIOSAMPLE_TYPE,
                                    rowdata_ref => $rd,
                           add_audit_parameters => 1
                                        );         
}


sub get_sample_type_id {
  my $this = shift;
  my $type = shift;
  my ( $id ) = $this->getSBEAMS()->selectrow_array( <<"  END" );
  SELECT biosample_type_id FROM $TBBM_BIOSAMPLE_TYPE
  WHERE biosample_type_name = '$type'
  END
  return $id;
}

#+
# Routine for inserting biosample
#
#-
#sub insertBiosamples {
#  my $this = shift;
#  my %args = @_;
#  my $p = $args{'wb_parser'} || die "Missing required parameter wb_parser";
#  $this->insertBiosamples( wb_parser => $p );
#}
#


#+
# Routine to cache biosource object,
#-
sub setBiosource {
  my $this = shift;

  # Use passed biosource if available
  $this->{_biosource} = shift || die 'Missing required biosource parameter';
}

#+
# Routine to fetch Biosource object
#-
sub getBiosource {
  my $this = shift;

  unless ( $this->{_biosource} ) {
    log->warn('getBiosource called, none defined'); 
    return undef;
  }
  return $this->{_biosource};
}

1;







__DATA__

# Attributes 
'Sample Setup Order'
'MS Sample Run Number'
'Name of Investigators'
'PARAM:time of sample collection '
'PARAM:meal'
'PARAM:alcohole'
'PARAM:smoke'
'PARAM:Date of Sample Collection'
'Study Histology'

# Bioource 
'ISB sample ID'
'Patient_id'
'External Sample ID'
'Name of Institute'
'species'
'age'
'gender'

'Sample type'

# Biosample
'amount of sample received'
'Location of orginal sample'

# Disease
'Disease:Breast cancer'
'Disease:Ovarian cancer'
'Disease:Prostate cancer'
'Disease:Blader Cancer'
'Disease:Skin cancer'
'Disease:Lung cancer'
'Disease: Huntington\'s Disease'
'diabetic'

# tissue_type
'heart'
'blood'
'liver'
'neuron'
'lung'
'bone'

biosource_disease
'Disease Stage'

#orphan
'Disease Info: Group'
'Prep Replicate id'
'Sample Prep Name'
'status of sample prep'
'date of finishing prep'
'amount of sample used in prep'
'Sample prep method'
'person prepared the samples'
'Volume of re-suspended sample'
'location of finished sample prep'
'MS Replicate Number'
'MS Run Name'
'status of MS'
'date finishing MS'
'Random Sample Run order'
'order of samples ran per day'
'MS run protocol'
'Volume Injected'
'location of data'
'status of Conversion'
'Date finishing conversion'
'name of raw files'
'location of raw files'
'name of mzXML'
'location of mzXML'
'person for MS analysis'
'date finishing alignment'
'location of alignment files'
'person for data analysis'
'peplist peptide peaks file location'
