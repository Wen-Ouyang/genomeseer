#!/usr/bin/perl -w
#run_casava.pl

use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);

my %panel2bed = ('panel1385'=>'UTSWV2.bed','panel1385v2'=>'UTSWV2_2.panelplus.bed',
		 'idthemev1'=>'heme_panel_probes.bed',
		 'idthemev2'=>'hemepanelV3.bed',
		 'idtcellfreev1'=>'panelcf73_idt.100plus.bed',
		 'medexomeplus'=>'MedExome_Plus.bed');

my %opt = ();
my $results = GetOptions (\%opt,'help|h','prjid|p=s');

if (!defined $opt{prjid} || $opt{help}) {
  $usage = <<EOF;
  usage: $0 -p prjid
      
      -p prjid -- this is the project name in /project/PHG/PHG_Illumina/BioCenter/ 140505_SN7001189_0117_AH7LRLADXX
      
EOF
  die $usage,"\n";
}

#identify the working directory
my @execdir = split(/\//,$0);
pop @execdir;
pop @execdir;
$baseDir = join("/",@execdir);

#determine the writing and processing directories
my $umi = 1;
my $prjid = $opt{prjid};
my $seqdatadir = "/project/PHG/PHG_Clinical/illumina/$prjid";
my $oriss = "/project/PHG/PHG_Clinical/illumina/sample_sheets/$prjid\.csv";
my $newss = "$seqdatadir\/$prjid\.csv";
my $capturedir = "/project/shared/bicf_workflow_ref/human/GRCh38/clinseq_prj";

#Relocate Run Data to New Location
system("mkdir /project/PHG/PHG_Clinical/illumina/$prjid");
system("ln -s /project/PHG/PHG_Illumina/BioCenter/$prjid/* /project/PHG/PHG_Clinical/illumina/$prjid");
system("mv /project/PHG/PHG_Clinical/illumina/$prjid/RunInfo.xml /project/PHG/PHG_Clinical/illumina/$prjid/RunInfo.xml.ori");

$umi = `grep "<Read Number=\\\"2\\\" NumCycles=\\\"14\\\" IsIndexedRead=\\\"Y\\\" />" /project/PHG/PHG_Illumina/BioCenter/$prjid/RunInfo.xml`;

#If UMI Fix RunInfo so that the UMI can be parsed to the ReadName
if ($umi) {
  open IN, "<$seqdatadir\/RunInfo.xml.ori" or die $!;
  open OUT, ">$seqdatadir\/RunInfo.xml" or die $!;
  while (my $line = <IN>) {
    chomp($line);
    if ($line =~ m/(\s+)<Read Number="(\d+)" /) {
      if ($2 eq 1) {
	print OUT $line,"\n";
      } elsif ($2 eq 2) {
	print OUT $1.qq{<Read Number="2" NumCycles="6" IsIndexedRead="Y" />},"\n";
      } elsif ($2 eq 3) {
	print OUT $1.qq{<Read Number="3" NumCycles="84" IsIndexedRead="N" />},"\n";
      } 
    }else {
      print OUT $line,"\n";
    }
  }
}else {
  system("cp /project/PHG/PHG_Clinical/illumina/$prjid/RunInfo.xml.ori /project/PHG/PHG_Clinical/illumina/$prjid/RunInfo.xml");
}

#Create New SampleSheet

open SS, "<$oriss" or die $!;
open SSOUT, ">$newss" or die $!;

my %sampleinfo;
my %stype;
my %spairs;
while (my $line = <SS>){
  chomp($line);
  $line =~ s/\r//g;
  $line =~ s/ //g;
  $line =~ s/,+$//g;
  if ($line =~ m/^\[Data\]/) {
    if ($umi) {
      print SSOUT join("\n","[Settings]","ReverseComplement,0","Read2UMILength,8"),"\n";
    }
    print SSOUT $line,"\n";
    $header = <SS>;
    $header =~ s/\r//g;
    chomp($header);
    $header =~ s/Sample_*/Sample_/g;
    print SSOUT $header,"\n";
    my @colnames = split(/,/,$header);
    while (my $line = <SS>) {
      chomp($line);
      $line =~ s/\r//g;
      $line =~ s/ //g;
      $line =~ s/,+$//g;
      my @row = split(/,/,$line);
      my %hash;
      foreach my $j (0..$#row) {
	$hash{$colnames[$j]} = $row[$j];
      }
      $hash{Sample_Project} = $hash{Project} if $hash{Project};
      $hash{Sample_Project} =~ s/\s*$//g;
      $hash{Assay} = lc($hash{Assay});
      $hash{Assay} = 'panel1385' if ($hash{Assay} eq 'dnaseqdevelopment');
      $hash{Assay} = 'panel1385v2' if ($hash{MergeName} =~ m/panel1385v2/);
      $hash{Assay} = 'idthemev2' if ($hash{MergeName} =~ m/IDTHemev2/);
      $hash{Assay} = 'panelrnaseq' if ($hash{MergeName} =~ m/panelrnaseq/);
      $hash{Assay} = 'wholernaseq' if ($hash{MergeName} =~ m/wholernaseq/);
      my @samplename = split(/_/,$hash{Sample_Name});
      unless ($hash{Class}) {
	$hash{Class} = 'tumor';
	$hash{Class} = 'normal' if ($hash{Sample_Name} =~ m/_N_/);
      }
      $hash{SubjectID} = $hash{Sample_Project};
      unless ($hash{MergeName}) {
	$hash{MergeName} = $hash{Sample_Name};
	if ($samplename[-1] =~ m/^[A|B|C|D]$/) {
	  pop @samplename;
	  $hash{MergeName} = join("_",@samplename);
	}
      }
      my $clinres = 'cases';
      $hash{VcfID} = $hash{SubjectID}."_".$prjid;
      if (($hash{Description} && $hash{Description} =~ m/research/i) ||
	  ($hash{Sample_Name} !~ m/ORD/ && $hash{SubjectID} !~ m/GM12878|ROS/)) {
	  $clinres = 'researchCases';
      }
      $hash{ClinRes} = $clinres;
      unless ($umi) {
	  $hash{Sample_Name} = $hash{Sample_Name}."_ClarityID-".$hash{Sample_ID};
      }
      $hash{Sample_ID} = $hash{Sample_Name};
      $stype{$hash{SubjectID}} = $hash{Case};
      $spairs{$hash{SubjectID}}{lc($hash{Class})}{$hash{MergeName}} = 1;
      $sampleinfo{$hash{Sample_Name}} = \%hash;
      push @{$samples{$hash{Assay}}{$hash{SubjectID}}}, $hash{Sample_Name};
      
      my @newline;
      foreach my $j (0..$#row) {
	  push @newline, $hash{$colnames[$j]};
      }
      print SSOUT join(",",@newline),"\n";
    }
  } else {
      print SSOUT $line,"\n";
  }
}
close SSOUT;

#create a batch 

open CAS, ">$seqdatadir\/run_$prjid\.sh" or die $!;
print CAS "#!/bin/bash\n#SBATCH --job-name $prjid\n#SBATCH -N 1\n";
print CAS "#SBATCH -t 14-0:0:00\n#SBATCH -o $prjid.out\n#SBATCH -e $prjid.err\n";
print CAS "source /etc/profile.d/modules.sh\n";
print CAS "module load bcl2fastq/2.17.1.14 nextflow/0.31.0 vcftools/0.1.14 samtools/1.6\n";

print CAS "bcl2fastq --barcode-mismatches 0 -o /project/PHG/PHG_Clinical/illumina/$prjid --no-lane-splitting --runfolder-dir $seqdatadir --sample-sheet $newss &> $seqdatadir\/bcl2fastq_$prjid\.log\n";
print CAS "mkdir /project/PHG/PHG_BarTender/bioinformatics/demultiplexing/$prjid\n" unless (-e "/project/PHG/PHG_BarTender/bioinformatics/demultiplexing/$prjid");
print CAS "cp -R /project/PHG/PHG_Clinical/illumina/$prjid\/Reports /project/PHG/PHG_BarTender/bioinformatics/demultiplexing/$prjid\n" unless (-e "/project/PHG/PHG_BarTender/bioinformatics/demultiplexing/$prjid/Reports");
print CAS "cp -R /project/PHG/PHG_Clinical/illumina/$prjid\/Stats /project/PHG/PHG_BarTender/bioinformatics/demultiplexing/$prjid\n" unless (-e "/project/PHG/PHG_BarTender/bioinformatics/demultiplexing/$prjid/Stats");

my %completeout; 
my %control;
my %completeout_somatic;

my $prodir = "/project/PHG/PHG_Clinical/processing";
my $outdir = "$prodir\/$prjid/fastq";
my $outnf = "$prodir\/$prjid/analysis";
my $workdir = "$prodir\/$prjid/work";
system("mkdir $prodir\/$prjid") unless (-e "$prodir\/$prjid");
system("mkdir $outdir") unless (-e $outdir);
system("mkdir $outnf") unless (-e $outnf);
system("mkdir $workdir") unless (-e $workdir);
print CAS "cd $prodir\/$prjid\n";

open TNPAIR, ">$outdir\/design_tumor_normal.txt" or die $!;
my $tnpairs = 0;
print TNPAIR join("\t",'PairID','VcfID','TumorID','NormalID','TumorBAM','NormalBAM',
		  'TumorFinalBAM','NormalFinalBAM'),"\n";
foreach my $subjid (keys %spairs) {
  my @ctypes = keys %{$spairs{$subjid}};
  if ($spairs{$subjid}{tumor} && $spairs{$subjid}{normal}) {
    my @tumors = keys %{$spairs{$subjid}{tumor}};
    my @norms = keys %{$spairs{$subjid}{normal}};
    my $pct = 0;
    foreach $tid (@tumors) {
      foreach $nid (@norms) {
	my $pair_id = $subjid;
	if ($pct > 1) {
	  $pair_id .= ".$pct";
	}
	print TNPAIR join("\t",$pair_id,$pair_id."_".$prjid,$tid,$nid,$tid.".bam",
			  $nid.".bam",$tid.".final.bam",$nid.".final.bam"),"\n";
	$pct ++;
	$tnpairs ++;
      }
    }
  }
}
close TNPAIR;

foreach $dtype (keys %samples) {
  open SSOUT, ">$outdir\/$dtype\.design.txt" or die $!;
  print SSOUT join("\t","SampleID",'SampleID2','SampleName','VcfID','FamilyID','FqR1','FqR2','BAM','FinalBAM'),"\n";
  my %thash;
  foreach $project (keys %{$samples{$dtype}}) {
    my $datadir =  "/project/PHG/PHG_Clinical/illumina/$prjid/$project/";
    foreach $samp (@{$samples{$dtype}{$project}}) {
      my %info = %{$sampleinfo{$samp}};
      if($info{SubjectID} =~ m/GM12878/){ #Positive Control
	  $control{$info{MergeName}}=['GM12878',$dtype];
      }
      print CAS "ln -s $datadir/$samp*_R1_*.fastq.gz $outdir\/$samp\.R1.fastq.gz\n";
      print CAS "ln -s $datadir/$samp*_R2_*.fastq.gz $outdir\/$samp\.R2.fastq.gz\n";
      unless (-e "$outnf\/$info{SubjectID}") {
	system("mkdir $outnf\/$info{SubjectID}");
      }
      unless (-e "$outnf\/$info{SubjectID}/fastq") {
	  system("mkdir $outnf\/$info{SubjectID}/fastq");
      }
      print CAS "ln -s $datadir/$samp*_R1_*.fastq.gz $outnf\/$info{SubjectID}/fastq\/$samp\.R1.fastq.gz\n";
      print CAS "ln -s $datadir/$samp*_R2_*.fastq.gz $outnf\/$info{SubjectID}/fastq\/$samp\.R2.fastq.gz\n";
      print SSOUT join("\t",$info{MergeName},$info{Sample_ID},$info{Sample_Name},$info{VcfID},
		       $info{SubjectID},"$samp\.R1.fastq.gz","$samp\.R2.fastq.gz",
		       $info{MergeName}.".bam",$info{MergeName}.".final.bam"),"\n";
    }
  }
  close SSOUT;
  my $mdup = 'picard';
  $mdup = 'fgbio_umi' if ($umi);
  $mdup = 'skip' if ($dtype =~ m/panelrnaseq/);
  my $germopts = '';
  my $rnaopts = '';
  my $capture='';
  unless ($dtype =~ /rna/) { 
    $capture = "$capturedir\/$panel2bed{$dtype}";
    my $alignwf = "$baseDir\/alignment.nf";
    unless ($umi) {
	$alignwf = "$baseDir\/alignmentV1.nf";
    }
    print CAS "nextflow -C $baseDir\/nextflow.config run -w $workdir $alignwf --design $outdir\/$dtype\.design.txt --capture $capture --input $outdir --output $outnf --markdups $mdup > $outnf\/$dtype\.nextflow_alignment.log\n";
  } elsif ($dtype =~ m/rnaseq/) {
    $rnaopts .= " --bamct skip " if ($dtype =~ m/whole/);
    print CAS "nextflow -C $baseDir\/nextflow.config run -w $workdir $baseDir\/rnaseq.nf --design $outdir\/$dtype\.design.txt --input $outdir --output $outnf $rnaopts --markdups $mdup > $outnf\/$dtype\.nextflow_rnaseq.log\n";
    $germopts = " --genome /project/shared/bicf_workflow_ref/human/GRCh38/hisat_index --nuctype rna --callsvs skip";
  }
  foreach $project (keys %spairs) {
    foreach $class (keys  %{$spairs{$project}}) {
      foreach $samp (keys %{$spairs{$project}{$class}}) {
	print CAS "mv $outnf\/$samp\.* $outnf\/$samp\_* $outnf\/$project\/$samp\n";
      }
    }
  }
  print CAS "ln -s $outnf\/*/*/*.bam $outnf\n";
  if($dtype =~ m/rnaseq/){  
    print CAS "nextflow -C $baseDir\/nextflow.config run -w $workdir $baseDir\/tumoronly.nf --design $outdir\/$dtype\.design.txt $germopts --projectid _${prjid} --input $outnf $capture --output $outnf > $outnf\/$dtype\.nextflow_tumoronly.log &\n";
  }
  else{
    print CAS "nextflow -C $baseDir\/nextflow.config run -w $workdir $baseDir\/tumoronly.nf --design $outdir\/$dtype\.design.txt $germopts --projectid _${prjid} --input $outnf --targetpanel $capture --output $outnf > $outnf\/$dtype\.nextflow_tumoronly.log &\n";
  }
}
print CAS "nextflow -C $baseDir\/nextflow.config run -w $workdir $baseDir\/somatic.nf --design $outdir\/design_tumor_normal.txt --projectid _${prjid} --input $outnf --output $outnf > $outnf\/nextflow_somatic.log &\n" if ($tnpairs);
print CAS "wait\n";

my $controlfile = $outnf."/GM12878/GM12878_".$prjid.".germline.vcf.gz";
foreach my $sampid (keys %control){
    my ($sampname,$dtype) = @{$control{$ctrls}};
    
    print CAS "cd $outnf\/GM12878\n";
    print CAS "vcf-subset -c ",$sampid," ",$controlfile," |bgzip > ",$sampid.".annot.vcf.gz\n";
    print CAS "bash $baseDir\/scripts/snsp.sh -p $sampid -r $capturedir -t $capturedir\/$panel2bed{$control{$sampid}[1]}\n";
}

print CAS "cd $outnf\n";

foreach my $case(keys %stype){
	if($stype{$case} eq 'true'){
		print CAS "rsync -avz $case /archive/PHG/PHG_Clinical/cases\n";
	}
}
print CAS "cd $prodir\/$prjid\n";
print CAS "rsync -rlptgoD --exclude=\"*fastq.gz*\" --exclude \"*work*\" --exclude=\"*bam*\" $prodir\/$prjid /project/PHG/PHG_BarTender/bioinformatics/seqanalysis/\n";
print CAS "perl $baseDir\/scripts/create_properties_run.pl -p $prjid -d /project/PHG/PHG_BarTender/bioinformatics/seqanalysis\n";

foreach $project (keys %spairs) {
  foreach $class (keys  %{$spairs{$project}}) {
    foreach $samp (keys %{$spairs{$project}{$class}}) {
	print CAS (qq{curl "http://nuclia.biohpc.swmed.edu:8080/NuCLIAVault/addPipelineResultsWithProp?token=\$nucliatoken&propFilePath=/project/PHG/PHG_BarTender/bioinformatics/seqanalysis\/$opt{prjid}/$samp\.properties"\n});
    }
  }
}
close CAS
