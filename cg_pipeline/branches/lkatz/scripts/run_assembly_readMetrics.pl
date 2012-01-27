#!/usr/bin/env perl

# run_assembly_readMetrics.pl: puts out metrics for a raw reads file
# Author: Lee Katz <lkatz@cdc.gov>

package PipelineRunner;
my ($VERSION) = ('$Id: $' =~ /,v\s+(\d+\S+)/o);

my $settings = {
    appname => 'cgpipeline',
};
my $stats;

use strict;
no strict "refs";
use FindBin;
use lib "$FindBin::RealBin/../lib";
$ENV{PATH} = "$FindBin::RealBin:".$ENV{PATH};
use AKUtils qw(logmsg);

use Getopt::Long;
use File::Temp ('tempdir');
use File::Path;
use File::Spec;
use File::Copy;
use File::Basename;
use List::Util qw(min max sum shuffle);
use CGPipelineUtils;
use Data::Dumper;

$0 = fileparse($0);
local $SIG{'__DIE__'} = sub { my $e = $_[0]; $e =~ s/(at [^\s]+? line \d+\.$)/\nStopped $1/; die("$0: ".(caller(1))[3].": ".$e); };
sub logmsg {my $FH = $FSFind::LOG || *STDOUT; print $FH "$0: ".(caller(1))[3].": @_\n";}

exit(main());

sub main() {
  $settings = AKUtils::loadConfig($settings);
  die(usage($settings)) if @ARGV<1;

  my @cmd_options=qw(help);
  GetOptions($settings, @cmd_options) or die;

  for my $input_file(@ARGV){
    my $file=File::Spec->rel2abs($input_file);
    die("Input or file $file not found") unless -f $file;
  
    my %metrics=readMetrics($file,$settings);
    print Dumper \%metrics;
  }
  return 0;
}

sub readMetrics{
  my($file,$settings)=@_;
  my($seqs,$qual);
  my $ext=(split(/\./,$file))[-1];
  if($ext=~/fastq/){
    ($seqs,$qual)=readFastq($file,$settings);
  } else {
    die "$ext extension not supported";
  }

  my $seqCounter=0;
  my($totalReadLength,$maxReadLength,$totalReadQuality,$totalQualScores,$avgReadQualTotal)=(0,0);
  while(my($id,$seq)=each(%$seqs)){
    # read metrics
    my $readLength=length($seq);
    $totalReadLength+=$readLength;
    $maxReadLength=$readLength if($readLength>$maxReadLength);
    
    # quality metrics
    my $qualStr=$$qual{$id};
    die "Could not find qual for $id" if(!$qualStr);
    my @qual=map(ord($_)-33,split(//,$qualStr));
    my $sumReadQuality=sum(@qual);
    my $thisReadAvgQual=$sumReadQuality/$readLength;
    $avgReadQualTotal+=$thisReadAvgQual;
    $totalReadQuality+=$sumReadQuality;
    $totalQualScores+=$readLength;
    
    $seqCounter++;
    # TODO avg quality overall
  }
  my $avgReadLength=$totalReadLength/$seqCounter;
  my $avgQuality=$totalReadQuality/$totalQualScores;
  my $avgQualPerRead=$avgReadQualTotal/$seqCounter;

  my %metrics=(
    avgReadLength=>$avgReadLength,
    totalBases=>$totalReadLength,
    maxReadLength=>$maxReadLength,
    avgQuality=>$avgQuality,
    avgQualPerRead=>$avgQualPerRead,
  );
  return %metrics;
}

sub readFastq{
  my($fastq,$settings)=@_;
  my $seqs={};
  my $quals={};
  my $i=0;
  open(FASTQ,"<",$fastq) or die "Could not open the fastq $fastq because $!";
  while(my $id=<FASTQ>){
    my $sequence=<FASTQ>;
    my $plus=<FASTQ>;
    my $qual=<FASTQ>;
    $id=~s/^@//;
    $$seqs{$id}=$sequence;
    $$quals{$id}=$qual;
  }
  close FASTQ;
  return ($seqs,$quals);
}

sub usage{
  my ($settings)=@_;
  "Prints useful assembly statistics
  Usage: $0 reads.fasta
    A reads file can be fasta or fastq
    The quality file for a fasta file is assumed to be reads.fasta.qual
  "
}
